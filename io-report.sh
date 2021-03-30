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
		rm -rf "*.0" || true
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
	if [ -z "${4+x}" ]; then
		echo "usage error" >&2
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
	rm -rf "*.0" || true
	echo ${cmd} >> ${log}
	local output=`${cmd} | tee -a ${log}`
	local out=`echo "${output}" | { grep IOPS || test $? == 1; } | awk -F ': ' '{print $2}'`
	local iops=`echo "${out}" | awk -F ',' '{print $1}'`
	local iotp=`echo "${out}" | awk '{print $2}'`
	local lats=`echo "${output}" | grep "lat (usec): " | awk -F ', ' '{print $2 " "$3}'`
	local clat=`echo "${lats}" | awk 'NR==1{print}'`
	local lat=`echo "${lats}" | awk 'NR==2{print}'`
	local lat_99=`echo "${output}" | grep "99.99th=" | sed 's/ *//' | sed 's/|//' | sed 's/ //' | sed 's/ //'`
	echo "${iops} ${iotp}"
	echo "clat (usec): ${clat}"
	echo "lat (usec): ${lat}"
	echo "${lat_99}"
}

function mixed_workload()
{
	local log="${1}"

	threads_write_1m_seq=("1" "2" "4" "8")
	threads_write_64k_seq=("1" "2" "4")

	for t1 in ${threads_write_1m_seq[@]}
	do
		for t2 in ${threads_write_64k_seq[@]}
		do
			rm -rf "*.0" || true
			_exec_mixed_workload "300s" "8G" "${log}" "${t1}" "${t2}"
		done
	done
}

function _exec_mixed_workload()
{
	local sec="${1}"
	local size="${2}"
	local log="${3}"
	local jobs_1m="${4}"
	local jobs_64k="${5}"

	local cmd="fio -size="${size}" -ramp_time=10 -randseed=0 -time_based -runtime="${sec}" \
				-name=write_1m_seq -rw=write -bs=1m -fallocate=posix -numjobs="${jobs_1m}" \
				-name=write_64k_seq -rw=write -bs=64k -fdatasync=1 -numjobs="${jobs_64k}" \
				-name=read_1m_seq -rw=read -bs=1m -numjobs=1 \
				-name=read_64k_seq -rw=read -bs=64k -numjobs=1 \
				-name=read_4k_rand -rw=randread -bs=4k -numjobs=1"

	echo "====================" >> ${log}
	rm -rf "*.0" || true
	echo ${cmd} >> ${log}
	local output=`${cmd} | tee -a ${log} | { grep IOPS || test $? == 1; } | awk -F ': ' '{print $2}'`
	local iops=`echo "${output}" | awk -F ',' '{print $1}'`
	local iotp=`echo "${output}" | awk '{print $2}'`
	echo "[mixed workload, write_1m_seq_jobs:${jobs_1m}, write_64k_seq_jobs:${jobs_64k}]"
	echo "Jobs: write_1m_seq, write_64k_seq, read_1m_seq, read_64k_seq, read_4k_rand"
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

function generate_disk_info()
{
	local log="disk.info.log"
	echo "==========smartctl==========" >> ${log}
	local info=`smartctl -i ${1}`
	echo "${info}" >> ${log}
	echo "==========fdisk==========" >> ${log}
	local info=`fdisk -l`
	echo "${info}" >> ${log}
}

## main entry

function io_trait()
{
	local dir="${1}"

	mkdir -p "${dir}"
	cd "${dir}"
	local disk=`get_device "."`

	check_all_installed
	generate_disk_info ${disk}

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
