#!/usr/bin/env bash

set -euf -o pipefail

script_dir="$(dirname "$(realpath "$0")")"
input_file="${script_dir}/input.txt"
config_dir="${script_dir}/conf"
output_dir_prefix="${script_dir}/out"
output_dir=''
syslog_ng=''
syslog_ng_ctl=''
syslog_ng_loggen=''
test_run_count=3

print_error()
{
    printf '%s\n' "$*" >&2
}

get_executable_path()
{
    local executable_name="$1"
    local executable_path

    executable_path="$(command -v "${executable_name}" || true)"

    if [[ -z "${executable_path}" ]]
    then
        print_error "Executable '${executable_name}' not found!" 'Exiting...'

        exit 1
    fi

    printf '%s' "${executable_path}"
}

check_prerequisites()
{
    local prerequisites=(
        'cp'
        'date'
        'grep'
        'head'
        'loggen'
        'mkdir'
        'pgrep'
        'syslog-ng'
        'syslog-ng-ctl'
        'timeout'
        'uname'
    )

    for prerequisite in "${prerequisites[@]}"
    do
        get_executable_path "${prerequisite}" > /dev/null
    done
}

setup_output_dir()
{
    output_dir="${output_dir_prefix}/$(date '+%Y-%m-%d_%H-%M-%S')"

    if [[ -d "${output_dir}" ]]
    then
        print_error                                              \
            "Output directory ('${output_dir}') already exists!" \
            'Exiting...'

        exit 2
    fi

    mkdir -p "${output_dir}"

    for ((i=0; i < test_run_count; i++))
    do
        mkdir "${output_dir}/run_$((i + 1))"
    done
}

set_syslog_ng_paths()
{
    syslog_ng="$(get_executable_path 'syslog-ng')"
    syslog_ng_ctl="$(get_executable_path 'syslog-ng-ctl')"
    syslog_ng_loggen="$(get_executable_path 'loggen')"
}

save_system_info()
{
    "${syslog_ng}" --version > "${output_dir}/syslog-ng.version"
    uname -a > "${output_dir}/uname.out"

    for _file in '/etc/os-release' '/proc/cpuinfo'
    do
        if [[ -f "${_file}" ]]
        then
            cp "${_file}" "${output_dir}/"
        fi
    done
}

stop_syslog_ng()
{
    local timeout_in_sec="${1:-60}"
    local syslog_ng_pids
    local exit_status=0

    syslog_ng_pids="$(pgrep 'syslog-ng' || true)"

    if [[ -n "${syslog_ng_pids}" ]]
    then
        "${syslog_ng_ctl}" stop || true
    fi

    timeout "${timeout_in_sec}"                                                                       \
        /usr/bin/env bash -c "until ! \"${syslog_ng_ctl}\" stats > /dev/null 2>&1 ; do sleep 1; done" \
        || exit_status="$?"

    if ((exit_status != 0))
    then
        print_error                                                  \
            "Could not stop syslog-ng in ${timeout_in_sec} seconds!" \
            'Exiting...'

        exit 3
    fi
}

wait_for_syslog_ng_to_start()
{
    local timeout_in_sec="${1:-60}"
    local exit_status=0

    timeout "${timeout_in_sec}"                                                                      \
        /usr/bin/env bash -c "until \"${syslog_ng_ctl}\" stats > /dev/null 2>&1 ; do sleep 1 ; done" \
        || exit_status="$?"

    if ((exit_status != 0))
    then
        print_error                                                 \
            "syslog-ng did not start in ${timeout_in_sec} seconds!" \
            'Exiting...'

        exit 3
    fi
}

get_file_names_in_directory_by_extension()
{
    local directory="$1"
    local extension=".$2"

    (
        cd "${directory}"

        set +f

        for _file in $(printf '%s\n' *"${extension}")
        do
            printf '%s\n' "$_file"
        done

        set -f
    )
}

run_benchmark()
{
    local log_files_to_remove=(
        '/var/log/fromnet1'
        '/var/log/fromnet2'
        '/var/log/fromnet3'
        '/var/log/fromnet4'
    )

    for ((i=0; i < test_run_count; i++))
    do
        while IFS= read -r line
        do
            config_name="${line/,*/}"
            loggen_parameters_list=()
            loggen_pids=()

            "${syslog_ng}" --no-caps -f "${config_dir}/${config_name}"

            wait_for_syslog_ng_to_start 10

            IFS=',' read -r -a loggen_parameters_list <<< "${line#*,}"

            for ((j=0; j < ${#loggen_parameters_list[@]}; j++))
            do
                loggen_parameter_list="${loggen_parameters_list[${j}]}"
                loggen_output_path="${loggen_parameter_list// /_}"
                loggen_output_path="${loggen_output_path//-/}"
                loggen_output_path="${loggen_output_path//=/_}"
                loggen_output_path="${output_dir}/run_$((i + 1))/${config_name}.${loggen_output_path}.$((j + 1)).csv"
                loggen_arguments=()

                IFS=' ' read -r -a loggen_arguments <<< "${loggen_parameter_list}"

                "${syslog_ng_loggen}" "${loggen_arguments[@]}" &> "${loggen_output_path}" &

                loggen_pids+=($!)
            done

            for loggen_pid in "${loggen_pids[@]}"
            do
                wait "${loggen_pid}"
            done

            stop_syslog_ng 10

            for log_file_to_remove in "${log_files_to_remove[@]}"
            do
                rm -f "${log_file_to_remove}" || true
            done
        done < "${input_file}"
    done
}

sum_results()
{
    local result_file_list
    local result_files=()
    local result_file_lists=()
    local output_file="${output_dir}/results.csv"

    for ((i=0; i < test_run_count; i++))
    do
        result_file_lists+=("$(get_file_names_in_directory_by_extension "${output_dir}/run_$((i + 1))" 'csv')")
    done

    result_file_list="${result_file_lists[0]}"

    for other_result_file_list in "${result_file_lists[@]}"
    do
        if [[ "${result_file_list}" != "${other_result_file_list}" ]]
        then
            print_error                                                      \
                'The number of result files is different between test runs!' \
                'Exiting...'

            exit 4
        fi
    done

    mapfile -t result_files <<< "${result_file_list}"

    for result_file in "${result_files[@]}"
    do
        config_name="${result_file/.*/}"
        loggen_parameters="${result_file#*.}"
        loggen_parameters="${loggen_parameters%.*}"
        loggen_parameters="${loggen_parameters%.*}"
        loggen_num="${result_file%.*}"
        loggen_num="${loggen_num##*.}"

        printf                                                  \
            '%s'                                                \
            "${config_name},${loggen_parameters},${loggen_num}" \
            >> "${output_file}"

        measured_values=''

        for ((i=0; i < test_run_count; i++))
        do
            _stat="$(
                grep 'average rate' "${output_dir}/run_$((i + 1))/${result_file}" \
                | head -1
            )"

            _stat="${_stat##*average rate = }"
            _stat="${_stat%% *}"

            measured_values="${measured_values},${_stat}"
        done

        printf '%s\n' "${measured_values}" >> "${output_file}"
    done
}

main()
{
    check_prerequisites
    set_syslog_ng_paths
    setup_output_dir
    stop_syslog_ng 10
    save_system_info
    run_benchmark
    sum_results
}

main
