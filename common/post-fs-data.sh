#!/system/bin/sh

# MagiskHide Props Config
# Copyright (c) 2018-2019 Didgeridoohan @ XDA Developers
# Licence: MIT

MODPATH=${0%/*}
BOOTSTAGE="post"

# Load functions
. $MODPATH/util_functions.sh

# Variables
MODULESPATH=$(dirname "$MODPATH")

# Start logging
log_start
bb_check

# Clears out the script check file
rm -f $RUNFILE
touch $RUNFILE

# Clears out the script control file
touch $POSTCHKFILE

# Checks the reboot and print update variables in propsconf_late
if [ "$REBOOTCHK" == 1 ]; then
	replace_fn REBOOTCHK 1 0 $LATEFILE
fi
if [ "$PRINTCHK" == 1 ]; then
	replace_fn PRINTCHK 1 0 $LATEFILE
fi

# Check for the boot script and restore backup if deleted, or if the resetfile is present
if [ ! -f "$LATEFILE" ] || [ -f "$RESETFILE" ]; then
	if [ -f "$RESETFILE" ]; then
		RSTTXT="Resetting"
		rm -f $RESETFILE
	else
		RSTTXT="Restoring"
		log_handler "late_start service boot script not found."
	fi	
	log_handler "$RSTTXT late_start service boot script (${LATEFILE})."
	cp -af $MODPATH/propsconf_late $LATEFILE >> $LOGFILE 2>&1
fi

# Checks for the Universal SafetyNet Fix module and similar modules editing the device fingerprint
PRINTMODULE=false
for USNF in $USNFLIST; do
	if [ -d "$MODULESPATH/$USNF" ]; then
		NAME=$(get_file_value $MODULESPATH/$USNF/module.prop "name=")
		log_handler "'$NAME' installed (modifies the device fingerprint)."
		PRINTMODULE=true
	fi
done
if [ "$PRINTMODULE" == "true" ]; then
	replace_fn FINGERPRINTENB 1 0 $LATEFILE
	replace_fn PRINTMODULE 0 1 $LATEFILE
	log_handler "Fingerprint modification disabled."
else
	replace_fn FINGERPRINTENB 0 1 $LATEFILE
	replace_fn PRINTMODULE 1 0 $LATEFILE
fi

# Get default values
log_handler "Checking device default values."

# Save default file values in propsconf_late
for ITEM in $VALPROPSLIST; do
	TMPPROP=$(get_prop_type $ITEM | tr '[:lower:]' '[:upper:]')
	ORIGPROP="ORIG${TMPPROP}"
	ORIGTMP="$(get_file_value $LATEFILE "${ORIGPROP}=")"
	CURRPROP="CURR${TMPPROP}"
	CURRTMP="$(resetprop $ITEM)"
	replace_fn $ORIGPROP "\"$ORIGTMP\"" "\"$CURRTMP\"" $LATEFILE
done
log_handler "Default values saved to $LATEFILE."

# Check if default file values are safe
replace_fn FILESAFE 0 1 $LATEFILE
for V in $PROPSLIST; do
	FILEVALUE=$(resetprop $V)
	log_handler "Checking ${V}=${FILEVALUE}"
	safe_props $V $FILEVALUE
	if [ "$SAFE" == 0 ]; then
		echo "Prop $V set to triggering value in prop file." >> $LOGFILE 2>&1
		replace_fn FILESAFE 1 0 $LATEFILE
	else
		if [ -z "$FILEVALUE" ]; then
			echo "Could not retrieve value for prop $V." >> $LOGFILE 2>&1
		elif [ "$SAFE" == 1 ]; then
			echo "Prop $V set to \"safe\" value in prop file." >> $LOGFILE 2>&1
		fi
	fi
done
# Loading the new values
. $LATEFILE

# Checks for configuration file
config_file

# Edits prop values if set for post-fs-data
echo -e "\n----------------------------------------" >> $LOGFILE 2>&1
log_handler "Editing prop values in post-fs-data mode."
if [ "$OPTIONBOOT" == 1 ]; then
	# ---Setting/Changing fingerprint---
	if [ "$PRINTSTAGE" == 0 ]; then
		print_edit
	fi
	# ---Setting/Changing security patch date---
	if [ "$PATCHSTAGE" == 0 ]; then
		patch_edit
	fi
	# ---Setting device simulation props---
	if [ "$SIMSTAGE" == 0 ]; then
		dev_sim_edit
	fi
	# ---Setting custom props---
	custom_edit "CUSTOMPROPS"
fi
# Edit fingerprint if set for post-fs-data
if [ "$OPTIONBOOT" != 1 ] && [ "$PRINTSTAGE" == 1 ]; then
	print_edit
fi
# Edit security patch date if set for post-fs-data
if [ "$OPTIONBOOT" != 1 ] && [ "$PATCHSTAGE" == 1 ]; then
	patch_edit
fi
# Edit simulation props if set for post-fs-data
if [ "$OPTIONBOOT" != 1 ] && [ "$SIMSTAGE" == 1 ]; then
	dev_sim_edit
fi
# Edit custom props set for post-fs-data
custom_edit "CUSTOMPROPSPOST"
# Deleting props
prop_del
echo -e "\n----------------------------------------" >> $LOGFILE 2>&1

# Edits build.prop
if [ "$FILESAFE" == 0 ]; then
	log_handler "Checking for conflicting build.prop modules."
	# Checks if any other modules are using a local copy of build.prop
	BUILDMODULE=false
	MODID=$(get_file_value $MODPATH/module.prop "id=")
	for D in $(ls $MODULESPATH); do
		if [ $D != "$MODID" ]; then
			if [ -f "$MODULESPATH/$D/system/build.prop" ] || [ "$D" == "safetypatcher" ]; then
				NAME=$(get_file_value $MODULESPATH/$D/module.prop "name=")
				log_handler "Conflicting build.prop editing in module '$NAME'."
				BUILDMODULE=true
			fi
		fi
	done
	if [ "$BUILDMODULE" == "true" ]; then
		replace_fn BUILDPROPENB 1 0 $LATEFILE
	else
		replace_fn BUILDPROPENB 0 1 $LATEFILE
	fi

	# Copies the stock build.prop to the module. Only if set in propsconf_late.
	if [ "$BUILDPROPENB" == 1 ] && [ "$BUILDEDIT" == 1 ]; then
		log_handler "Stock build.prop copied to module."
		cp -af $MIRRORLOC/build.prop $MODPATH/system/build.prop >> $LOGFILE 2>&1
		
		# Edits the module copy of build.prop
		log_handler "Editing build.prop."
		# ro.build props
		change_prop_file "build"
		# Fingerprint
		if [ "$MODULEFINGERPRINT" ] && [ "$SETFINGERPRINT" == "true" ] && [ "$FINGERPRINTENB" == 1 ]; then
			PRINTSTMP="$(grep "$ORIGFINGERPRINT" $MIRRORLOC/build.prop)"
			for ITEM in $PRINTSTMP; do
				replace_fn $(get_eq_left "$ITEM") $(get_eq_right "$ITEM") $(echo $MODULEFINGERPRINT | sed 's|\_\_.*||') $MODPATH/system/build.prop && log_handler "$(get_eq_left "$ITEM")=$(echo $MODULEFINGERPRINT | sed 's|\_\_.*||')"
			done
		fi
	else
		rm -f $MODPATH/system/build.prop
		log_handler "Build.prop editing disabled."
	fi
else
	rm -f $MODPATH/system/build.prop
	log_handler "Prop file editing disabled. All values ok."
fi

log_script_chk "post-fs-data.sh module script finished.\n\n===================="

# Deletes the post-fs-data control file
rm -f $POSTCHKFILE