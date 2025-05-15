# Benchmark Parser and Visualization

A simple tool to parse and visualize CPU, memory, and network benchmarks.

## Directory Structure

```
├── main.py           # Main entry point
├── parsers.py        # Benchmark log parsing functions
├── requirements.txt  # All python requirements
└── visualization.py  # Visualization generation functions
```

## Usage

```bash
# Parse cpu and memory output
python main.py
```

## Input Log File Structure

The script expects the following log file structure:

1. CPU benchmarks from Sysbench 2.
2. Memory benchmarks from Sysbench and stress-ng
3. Network benchmarks from iperf3 and ping

## Output

The script generates the following output files:

1. CSV summaries of benchmark results
2. PNG visualizations of key metrics
   - CPU events per second
   - Memory transfer rates

All outputs are saved to the specified output directory.
