# sngbench

Shell script to performance test your syslog-ng. It runs from localhost and uses loggen, the bundled benchmarking and testing tool of syslog-ng. It comes with two configuration (a performance optimized and a more realistic), and you are free to extend it with your configurations.

## files

 * ```conf``` directory: syslog-ng configuration files
 * ```out``` directory: where measurement results are shaved. Some examples are included
 * ```input.txt``` file: describes the list of tests
 * ```sngbench.sh``` file: script to run the benchmarks
 * ```sngsum.sh``` file: script to process the benchmark output
 
Notes:
 * sngbench.sh expects conf/out/input.txt to be in the current directory
 * sngsum.sh expects an output file name and three input directory names as parameters

Which aslo means that you need to run sngbench three times. Currently, part of the "processing" is in the LibreCalc table (averaging the three runs, adding up the results if there were multiple loggen runs in parallel).

