#!/bin/bash

## basic spec report

function _io_test()
{
	local rw="${1}"
	local bs="${2}"
	local sec="${3}"
	local jobs="${4}"
	local log="${5}"
	local size="${6}"
	local rm="${7}"
	local fdatasync="${8:-0}"
	local cmd

    if [ `echo ${fdatasync} | grep "1"` ]; then
        cmd="fio -direct=0 -fdatasync=1 --fallocate=posix -rw="${rw}" -size="${size}" -numjobs="${jobs}" -bs="${bs}" -runtime="${sec}" -ramp_time=15 -randseed=0 -group_reporting -name=test -time_based"
    else
        cmd="fio -direct=1 -fdatasync=0 -rw="${rw}" -size="${size}" -numjobs="${jobs}" -bs="${bs}" -runtime="${sec}" -ramp_time=15 -randseed=0 -group_reporting -name=test -time_based"
    fi

	echo "====================" >> ${log}
	if [ `echo ${rm} | grep "1"` ]; then
		rm -rf "*.0"
	fi
	echo ${cmd} >> ${log}
	${cmd} | tee -a ${log} | { grep IOPS || test $? == 1; } | awk -F ': ' '{print $2}'
}

function _io_standard()
{
	local threads="${1}"
	local log="${2}"
	local sec="${3}"
	local size="${4}"
	local bs="${5}"
	local rm="${6}"

	local wl_w=`_io_test 'write' "${bs}" "${sec}" "${threads}" "${log}" "${size}" "${rm}"`
	local wl_sync=`_io_test 'write' "${bs}" "${sec}" "${threads}" "${log}" "${size}" "${rm}" "1"`
	local wl_r=`_io_test 'read'  "${bs}" "${sec}" "${threads}" "${log}" "${size}" "${rm}"`
	local wl_iops_w=`echo "${wl_w}" | awk -F ',' '{print $1}'`
	local wl_iops_sync=`echo "${wl_sync}" | awk -F ',' '{print $1}'`
	local wl_iops_r=`echo "${wl_r}" | awk -F ',' '{print $1}'`
	local wl_iotp_w=`echo "${wl_w}" | awk '{print $2}'`
	local wl_iotp_sync=`echo "${wl_sync}" | awk '{print $2}'`
	local wl_iotp_r=`echo "${wl_r}" | awk '{print $2}'`
	echo "${bs}, ${threads} threads: Write: ${wl_iops_w} ${wl_iotp_w}, WriteSync: ${wl_iops_sync} ${wl_iotp_sync}, Read: ${wl_iops_r} ${wl_iotp_r}"
}

function io_report()
{
	if [ -z "${5+x}" ]; then
		echo "[func io_report] usage: <func> test_file test_log each_test_sec test_file_size" >&2
		return 1
	fi

	local log="${1}"
	local sec="${2}"
	local size="${3}"
	local rm="${4}"

	t_arr=("1" "2" "4" "8" "16")
	bs_arr=("4k" "16k" "64k" "256k" "1m")

	for t in ${t_arr[@]}
	do
		for bs in ${bs_arr[@]}
		do
			_io_standard "${t}" "${log}" "${sec}" "${size}" "${bs}" "${rm}"
		done
	done
}
export -f io_report

## latency report

function _lat_workload()
{
	local run_sec="${1}"
	local threads="${2}"
	local bs="${3}"
	local rw="${4}"
	local fsize="${5}"
	local iops="${6}"
	local log="${7}"

	local cmd="fio -numjobs="${threads}" -size="${fsize}" -bs="${bs}" -direct=1 -rw="rand${rw}" -rate_iops="${iops}" \
		-name=test -group_reporting -runtime="${run_sec}" -ramp_time=15 -randseed=0 -time_based"
	echo "====================" >> ${log}
	rm -rf "*.0"
	echo ${cmd} >> ${log}
	local output=`${cmd} | tee -a ${log} | { grep IOPS || test $? == 1; } | awk -F ': ' '{print $2}'`
	local iops=`echo "${output}" | awk -F ',' '{print $1}'`
	local iotp=`echo "${output}" | awk '{print $2}'`
	echo "${iops} ${iotp}"
}

function mixed_workload()
{
	local log="${1}"

	threads=("1" "2" "4" "8")
	for t in ${threads[@]}
	do
		_seq_read_write_mixed_workload "300s" "${t}" "8G" "${log}" "1m" "1m" "posix"
	done

	threads=("1" "2" "4")
	for t in ${threads[@]}
	do
		_rand_read_write_mixed_workload "300s" "${t}" "8G" "${log}" "4k" "64k" 
	done

	_seq_read_write_mixed_workload "300s" "${t}" "8G" "${log}" "64k" "1m" "native"
}

function _seq_read_write_mixed_workload()
{
	local sec="${1}"
	local jobs="${2}"
	local size="${3}"
	local log="${4}"
	local read_bs="${5}"
	local write_bs="${6}"
	local allo="${7}"

	local cmd="fio -group_reporting -size="${size}" -runtime="${sec}" -direct=1 -fallocate="${allo}" -name=read_job -rw=read -bs="${read_bs}" -name=write_job -rw=write -numjobs="${jobs}" -bs="${write_bs}" -ramp_time=15 -randseed=0 -time_based"
	echo "====================" >> ${log}
	rm -rf "*.0"
	echo ${cmd} >> ${log}
	local output=`${cmd} | tee -a ${log} | { grep IOPS || test $? == 1; } | awk -F ': ' '{print $2}'`
	local iops=`echo "${output}" | awk -F ',' '{print $1}'`
	local iotp=`echo "${output}" | awk '{print $2}'`
	echo "[seq read + seq write write_jobs:${jobs} write_bs=${write_bs} read_bs:${read_bs}]"
	echo "${iops}"
	echo "${iotp}"
}

function _rand_read_write_mixed_workload()
{
	local sec="${1}"
	local jobs="${2}"
	local size="${3}"
	local log="${4}"
	local read_bs="${5}"
	local write_bs="${6}"

	local cmd="fio -group_reporting -size="${size}" -runtime="${sec}" -direct=1 -name=read_job -rw=randread -bs="${read_bs}" -name=write_job -rw=randwrite -numjobs="${jobs}" -bs="${write_bs}" -ramp_time=15 -randseed=0 -time_based"
	echo "====================" >> ${log}
	rm -rf "*.0"
	echo ${cmd} >> ${log}
	local output=`${cmd} | tee -a ${log} | { grep IOPS || test $? == 1; } | awk -F ': ' '{print $2}'`
	local iops=`echo "${output}" | awk -F ',' '{print $1}'`
	local iotp=`echo "${output}" | awk '{print $2}'`
	echo "[rand read + seq write write_jobs:${jobs} write_bs=${write_bs} read_bs:${read_bs}]"
	echo "${iops}"
	echo "${iotp}"
}

function io_lat_report()
{
	if [ -z "${4+x}" ]; then
		echo "[func io_report] usage: <func> test_file disk_name each_test_sec bw_threads iops_threads file_size" >&2
		return 1
	fi

	local disk="${1}"
	local run_sec="${2}"
	local fsize="${3}"
	local log="${4}"


	t_arr=("1" "8")
	bs_arr=("4k" "64k" "256k" "1m")
	iops_arr=("1000" "2000" "3000" "4000" "5000")

	for t in ${t_arr[@]}
	do
		for bs in ${bs_arr[@]}
		do
			for iops in ${iops_arr[@]}
			do
			echo "[w_bw_${t}t_${bs}bs_${iops}iops]"
			_lat_workload "${run_sec}" "${t}" "${bs}" "write" "${fsize}" "${iops}" "${log}"
			wait
			echo "[r_bw_${t}t_${bs}bs_${iops}iops]"
			_lat_workload "${run_sec}" "${t}" "${bs}" "read" "${fsize}" "${iops}" "${log}"
			wait
			done
		done
	done
}
export -f io_lat_report

## some tools

function get_device()
{
	local fs=$(df -k "${1}" | tail -1)

	local device=''
	local last=''
	local cached_mnt=''
	local cached_device=''

	local mnt=$(echo "${fs}" | awk '{ print $6 }')
	if [ "${cached_mnt}" != "${mnt}" ]; then
		local cached_mnt="${mnt}"

		local mnts=$(mount)
		local new_mnt="${mnt}"

		while [ -n "${new_mnt}" ]; do
			local new_mnt=$(echo "${mnts}" | grep " on ${mnt} " | awk '{ print $1 }')
			[ "${new_mnt}" = "${mnt}" ] && break
			if [ -n "${new_mnt}" ]; then
				local device="${new_mnt}"
				local mnt=$(df "${new_mnt}" 2> /dev/null | tail -1 | awk '{print $6 }')
				[ "${mnt}" = "${device}" -o "${mnt}" = "${last}" ] && break
				local last="${mnt}"
			fi
		done

		local cached_device="${device}"
	else
		local device="${cached_device}"
	fi

	echo "${device}"
}

function check_all_installed()
{
	local info=`fio --help 2>&1 | grep '--version'`
	if [ -z "${info}" ]; then
		echo "fio is not installed" >&2
		return 1
	fi
}

## main entry

function io_trait()
{
	local dir="${1}"

	mkdir "${dir}"
	cd "${dir}"
	local disk=`get_device "."`

	check_all_installed

	local log="./io-report.`hostname`.`basename ${disk}`.log"
	echo "IO trait report created by [io-report.sh]" > "${log}"
	echo "    host: `hostname`" >> "${log}"
	echo "    disk: ${disk}" >> "${log}"
	echo "    date: `date +%D-%T`" >> "${log}"
	echo "" >> "${log}"
	echo "Get involved:" >> "${log}"
	echo "    https://github.com/hunterlxt/io-report" >> "${log}"
	echo "Forked:" >> "${log}"
	echo "    https://github.com/innerr/io-report" >> "${log}"
	echo "" >> "${log}"

	echo "==> [basic io spec report] (size=10G, runtime=60s)" >> "${log}"
	io_report "fio.basic.log" "60" "10G" "1" >> "${log}"
	echo "" >> "${log}"
	echo "==> [cache detecting report] (size=10G, runtime=60s)" >> "${log}"
	io_report "fio.cache.log" "60" "10G" "0" >> "${log}"
	echo "" >> "${log}"
	echo "==> [latency report]" >> "${log}"
	io_lat_report "${disk}" "60" "10G" "fio.lat.log" >> "${log}"
	echo "" >> "${log}"
	echo "==> [mixed workload report]" >> "${log}"
	mixed_workload "fio.mixed.log" >> "${log}"
}
export -f io_trait

## user interface

set -eu
if [ "$#" != 1 ]; then
	echo "usage: <bin> test_dir" >&2
	exit 1
fi
io_trait "${1}"
