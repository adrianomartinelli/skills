#!/usr/bin/env bash
# Refuse a partition/QOS/walltime combination that sbatch would accept and the scheduler would then
# never start. Run it in front of sbatch:
#
#   bash <slurm-submit skill dir>/check-qos.sh <partition>[,<partition>...] [<qos>] <time> && sbatch ...
#
# On a cluster with EnforcePartLimits=NO, sbatch exits 0 and prints a job id for a QOS a partition
# does not allow, for the account's default QOS on a partition that does not allow it, and for a
# walltime over a QOS's MaxWall when that QOS lacks DenyOnLimit. Each job then pends forever with a
# policy reason in squeue and no error anywhere else. Omit <qos> to check the default QOS the job
# would get. The account is $SLURM_ACCOUNT, else your default account.
set -euo pipefail

# Slurm time -> seconds: MM, MM:SS, HH:MM:SS, D-HH, D-HH:MM, D-HH:MM:SS.
seconds() {
    local t=$1 d=0 h=0 m=0 s=0 f
    if [[ $t == *-* ]]; then
        d=${t%%-*}; t=${t#*-}
        IFS=: read -r -a f <<<"$t"
        h=${f[0]}; m=${f[1]:-0}; s=${f[2]:-0}
    else
        IFS=: read -r -a f <<<"$t"
        case ${#f[@]} in
            1) m=${f[0]} ;;
            2) m=${f[0]}; s=${f[1]} ;;
            *) h=${f[0]}; m=${f[1]}; s=${f[2]} ;;
        esac
    fi
    echo $(( ((10#$d * 24 + 10#$h) * 60 + 10#$m) * 60 + 10#$s ))
}

if [[ "${1:-}" == --selftest ]]; then
    for pair in 30=1800 05:30=330 02:00:00=7200 1-12=129600 1-12:30=131400 7-00:00:00=604800; do
        got=$(seconds "${pair%=*}")
        [[ "$got" == "${pair#*=}" ]] || { echo "seconds ${pair%=*}: $got, want ${pair#*=}" >&2; exit 1; }
    done
    echo "selftest ok" >&2
    exit 0
fi

if [[ $# -eq 2 ]]; then
    partitions=$1 qos="" time=$2
elif [[ $# -eq 3 ]]; then
    partitions=$1 qos=$2 time=$3
else
    echo "usage: check-qos.sh <partition>[,<partition>...] [<qos>] <time>" >&2
    exit 2
fi

account=${SLURM_ACCOUNT:-$(sacctmgr -n -P show user "$USER" format=defaultaccount)}
if [[ -z "$qos" ]]; then
    qos=$(sacctmgr -n -P show assoc user="$USER" account="$account" format=defaultqos | head -1)
    echo "no --qos given: the job gets the default QOS '$qos'" >&2
fi

# A multi-partition job may start on any of them, so every one must allow the QOS.
IFS=, read -r -a parts <<<"$partitions"
for partition in "${parts[@]}"; do
    info=$(scontrol show partition "$partition" -o 2>/dev/null) \
        || { echo "partition '$partition' does not exist." >&2; exit 1; }
    allowed=$(grep -oE 'AllowQos=[^ ]+' <<<"$info" | cut -d= -f2)
    if [[ "$allowed" != ALL && ",$allowed," != *",$qos,"* ]]; then
        echo "QOS '$qos' is not allowed on partition '$partition' (allows: $allowed)." >&2
        echo "sbatch would accept it and the job would pend forever." >&2
        exit 1
    fi
done

if ! sacctmgr -n -P show assoc user="$USER" account="$account" format=qos | tr ',' '\n' | grep -qx "$qos"; then
    echo "QOS '$qos' is not in account '$account''s QOS list." >&2
    exit 1
fi

maxwall=$(sacctmgr -n -P show qos "$qos" format=maxwall)
if [[ -n "$maxwall" ]] && (( $(seconds "$time") > $(seconds "$maxwall") )); then
    echo "--time=$time exceeds QOS '$qos' MaxWall $maxwall." >&2
    exit 1
fi

echo "ok: partitions=$partitions qos=$qos time=$time (MaxWall ${maxwall:-none})" >&2
