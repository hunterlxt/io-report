#!/bin/bash

## basic spec report

function _io_test()
{
	local rw="${1}"
	local bs="${2}"
	local sec="${3}"
	local jobs="${4}"
	local file="${5}"
	local log="${6}"
	local size="${7}"
	local fdatasync="${8:-0}"

	local cmd="fio -filename="${file}" -direct=1 -fdatasync="${fdatasync}" -rw="${rw}" -size="${size}" -numjobs="${jobs}" -bs="${bs}" -runtime="${sec}" -group_reporting -name=test"
	echo "<==========>" >> ${log}
	echo ${cmd} >> ${log}
	${cmd} | tee -a ${log} | { grep IOPS || test $? == 1; } | awk -F ': ' '{print $2}'
}

function _io_standard()
{
	local threads="$1"
	local file="${2}"
	local log="${3}"
	local sec="${4}"
	local size="${5}"
	local bs="${6}"

	local wl_w=`_io_test 'write' "${bs}" "${sec}" "${threads}" "${file}" "${log}" "${size}"`
	local wl_sync=`_io_test 'write' "${bs}" "${sec}" "${threads}" "${file}" "${log}" "${size}" "1"`
	local wl_r=`_io_test 'read'  "${bs}" "${sec}" "${threads}" "${file}" "${log}" "${size}"`
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

	local file="${1}"
	local log="${2}"
	local sec="${3}"
	local size="${4}"
	local threads="${5}"

	t_arr=("1" "2" "4" "8" "16")
	bs_arr=("4k" "16k" "64k" "256k" "1m")

	for t in ${t_arr[@]}
	do
		for bs in ${bs_arr[@]}
		do
			_io_standard "${t}" "${file}" "${log}" "${sec}" "${size}" "${bs}"
		done
	done
}
export -f io_report

## latency report

function _lat_workload()
{
	local run_sec="${1}"
	local file="${2}"
	local threads="${3}"
	local bs="${4}"
	local rw="${5}"
	local fsize="${6}"
	local iops="${7}"
	local log="${8}"

	local cmd="fio -threads="${threads}" -size="${fsize}" -bs="${bs}" -direct=1 -rw="rand${rw}" -rate_iops="${iops}" \
		-name=test -group_reporting -filename="${file}" -runtime="${run_sec}""
	echo "<==========>" >> ${log}
	echo ${cmd} >> ${log}
	local output=`${cmd} | tee -a ${log} | { grep IOPS || test $? == 1; } | awk -F ': ' '{print $2}'`
	local iops=`echo "${output}" | awk -F ',' '{print $1}'`
	local iotp=`echo "${output}" | awk '{print $2}'`
	echo "${iops} ${iotp}"
}

function mixed_workload()
{
	local file="${1}"
	local log="${2}"

	threads=("1" "2" "4" "8")
	for t in ${threads[@]}
	do
		_seq_read_write_mixed_workload "60s" "${t}" "16G" "${file}" "${log}" "1m" "1m" 
	done

	threads=("1" "2" "4")
	for t in ${threads[@]}
	do
		_rand_read_write_mixed_workload "60s" "${t}" "16G" "${file}" "${log}" "4k" "64k" 
	done

	_seq_read_write_mixed_workload "60s" "${t}" "16G" "${file}" "${log}" "4k" "1m" 
}

function _seq_read_write_mixed_workload()
{
	local sec="${1}"
	local jobs="${2}"
	local size="${3}"
	local file="${4}"
	local log="${5}"
	local read_bs="${6}"
	local write_bs="${7}"

	local cmd="fio -group_reporting -filename="${file}" -size="${size}" -runtime="${sec}" -direct=1 -name=read_job -rw=read -bs="${read_bs}" -name=write_job -rw=write -numjobs="${jobs}" -bs="${write_bs}""
	echo "<==========>" >> ${log}
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
	local file="${4}"
	local log="${5}"
	local read_bs="${6}"
	local write_bs="${7}"

	local cmd="fio -group_reporting -filename="${file}" -size="${size}" -runtime="${sec}" -direct=1 -name=read_job -rw=randread -bs="${read_bs}" -name=write_job -rw=randwrite -numjobs="${jobs}" -bs="${write_bs}""
	echo "<==========>" >> ${log}
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

	local file="${1}"
	local disk="${2}"
	local run_sec="${3}"
	local fsize="${4}"
	local log="${5}"


	t_arr=("1" "2" "4" "8" "16")
	bs_arr=("4k" "64k" "256k" "1m")
	iops_arr=("1000" "2000" "3000" "4000" "5000")

	for t in ${t_arr[@]}
	do
		for bs in ${bs_arr[@]}
		do
			for iops in ${iops_arr[@]}
			do
			echo "[w_bw_${t}t_${bs}bs_${iops}iops]"
			_lat_workload "${run_sec}" "${file}" "${t}" "${bs}" "write" "${fsize}" "${iops}" "${log}"
			wait
			echo "[r_bw_${t}t_${bs}bs_${iops}iops]"
			_lat_workload "${run_sec}" "${file}" "${t}" "${bs}" "read" "${fsize}" "${iops}" "${log}"
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
	touch "tempfile"
	local file=`readlink -f "tempfile"`
	local dir=`dirname "${file}"`
	local disk=`get_device "${dir}"`

	check_all_installed

	local log="./io-report.`hostname`.`basename ${disk}`.log"
	echo "IO trait report created by [io-report.sh]" > "${log}"
	echo "    host: `hostname`" >> "${log}"
	echo "    file: tempfile" >> "${log}"
	echo "    disk: ${disk}" >> "${log}"
	echo "    date: `date +%D-%T`" >> "${log}"
	echo "" >> "${log}"
	echo "Get involved:" >> "${log}"
	echo "    https://github.com/hunterlxt/io-report" >> "${log}"
	echo "Forked:" >> "${log}"
	echo "    https://github.com/innerr/io-report" >> "${log}"
	echo "" >> "${log}"

	echo "==> [basic io spec report] (size=16G, runtime=30s)" >> "${log}"
	io_report "tempfile" "tempfile.fio.basic.log" "30" "16G" "8" >> "${log}"
	echo "" >> "${log}"
	echo "==> [cache detecting report] (size=500M, runtime=15s)" >> "${log}"
	io_report "tempfile" "tempfile.fio.cache.log" "15" "500M" "8" >> "${log}"
	echo "" >> "${log}"
	echo "==> [latency report]" >> "${log}"
	io_lat_report "tempfile" "${disk}" "30" "16G" "tempfile.fio.lat.log" >> "${log}"
	echo "" >> "${log}"
	echo "==> [mixed workload report]" >> "${log}"
	mixed_workload "tempfile" "tempfile.fio.mixed.log" >> "${log}"
}
export -f io_trait

## user interface

set -eu
if [ "$#" != 1 ]; then
	echo "usage: <bin> test_dir" >&2
	exit 1
fi
io_trait "${1}"
