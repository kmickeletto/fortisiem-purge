#!/bin/bash
# ------------------------------------------------------------------
# [Ken Mickeletto] getPurge.sh
# Scans FortiSIEM eventdb on NFS for purgeable data
# Data expiration can be configured in days old
# ------------------------------------------------------------------
VERSION=1.1.2
SUBJECT=getPurge.sh
ARGS='[OPTIONAL -p | --purge]'
USAGE="Usage: $SUBJECT $ARGS"
USAGENOTES="Running without any arguments, script will only output directories that should be purged"

days=400
rptdays=30
base=/data/eventdb/
purge_threads=50
action_list=/tmp/action_list.tmp

rptday=$(echo "($(date +%s)/86400)-$rptdays" | bc)
day=$(echo "($(date +%s)/86400)-$days" | bc)
targetdate=$(( $day * 86400 ))
targetdate=$(date -d@$targetdate +%D)
rpttargetdate=$(( $rptday * 86400 ))
rpttargetdate=$(date -d@$rpttargetdate +%D)
mode=${1:-'--show'}

case "$mode" in
    --purge|-p)
        action_cmd=purge
        echo "$SUBJECT $VERSION"
        echo "$(date '+%D %T')"
        echo
        echo "Purging directories older than $targetdate and inline reports older than $rpttargetdate"
        ;;
    --show|-s)
        action_cmd=show
        >&2 echo "$SUBJECT $VERSION"
        >&2 echo
        >&2 echo "Showing directories older than $targetdate and inline reports older than $rpttargetdate"
        ;;
    --help|-h)
        echo "$SUBJECT $VERSION"
        echo "$USAGE"
        echo "$USAGENOTES"
        exit
        ;;
    *)
        echo "Unknown option"
        exit 1
        ;;
esac
rm -f $action_list
touch $action_list

show() {
    echo "$1"
}

purge() {
    echo "Beginning purge routine"
    if parallel 2>/dev/null 1>/dev/null; then
        echo "$1" | parallel -j${purge_threads} "echo {} & rm -fr {}"
        else
           echo "Unable to find parallel to run multi-threaded, running in single thread mode"
           sleep 5
       while read dir; do
           echo "Removing $dir"
               rm -fr "$dir"
           done <<< "$1"
    fi
}

fmt_base=${base//\//\\/}
${dir//${base}}
for dir in ${base}CUSTOMER_*/; do
    for subdir in $dir*/; do
        # default incident internal query report
        if [[ $subdir =~ \/report\/$ ]]; then
            for inner_subdir in $subdir*/; do
                #i300 i3600 i900 original
                if [[ $inner_subdir =~ (i300|i3600|i900)\/$ ]]; then
                    for day_dir in $inner_subdir*/; do
                        rpt_dir=$(perl -lne 'print $1 if /([0-9]{5})/' <<< $day_dir)
                        if [[ ${rpt_dir} =~ ^[0-9]{5}$ ]] && [[ $rpt_dir -lt $rptday ]]; then
                            echo "${day_dir}" >> $action_list
                        fi
                    done
                fi
            done
        else
            for day_dir in $subdir*/; do
                epoch_stamp=$(perl -lne 'print $1 if /([0-9]{5})/' <<< $day_dir)
                if [[ ${epoch_stamp} =~ ^[0-9]{5}$ ]] && [[ $epoch_stamp -lt $day ]]; then
                    echo "${day_dir}" >> $action_list
                fi
            done
        fi
    done
    for subdir in $dir*/; do
        # default incident internal query
        if [[ $subdir =~ \/(default|internal|incident)\/$ ]]; then
            for day_dir in $subdir*/; do
                if [[ ${day_dir} =~ ^[0-9]{5}$ ]] && [[ $day_dir -lt $day ]]; then
                    echo "${day_dir}" >> $action_list
                fi
            done
        fi
    done
    for subdir in $dir*/; do
        if [[ $subdir =~ \/query\/ ]]; then
            find $subdir -maxdepth 1 -type d -mtime +${days} >> /tmp/action_list.tmp
        fi
    done
done
$action_cmd "$(cat $action_list)"
