#!/usr/bin/env python3
"""
QNN log parser
Parses logs of inference for metrics extraction
"""

import sys
import struct
import argparse
import json
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple

class QNNLogParser:
    """
    QNN parser that searches for values around string positions
    to extract performance metrics from QNN profiling files
    """
    
    def __init__(self):
        # Target strings to search for and their corresponding metric names
        self.metric_patterns = {
            'QNN (deinit) time': {
                'key': 'qnn_deinit_time_us',
                'unit': 'microseconds',
                'type': 'timing'
            },
            'Accelerator (deinit) time': {
                'key': 'accelerator_deinit_time_us',
                'unit': 'microseconds',
                'type': 'timing'
            },
            'QNN Accelerator (deinit) time': {
                'key': 'qnn_accelerator_deinit_time_us',
                'unit': 'microseconds',
                'type': 'timing'
            },
            'RPC (deinit) time': {
                'key': 'rpc_deinit_time_us',
                'unit': 'microseconds',
                'type': 'timing'
            },
            'QNN (execute) time': {
                'key': 'qnn_execute_time_us',
                'unit': 'microseconds',
                'type': 'timing'
            },
            'Accelerator (execute excluding wait) time': {
                'key': 'accelerator_execute_excluding_wait_time_us',
                'unit': 'microseconds',
                'type': 'timing'
            },
            'Accelerator (execute) time': {
                'key': 'accelerator_execute_time_us',
                'unit': 'microseconds',
                'type': 'timing'
            },
            'QNN accelerator (execute) time': {
                'key': 'qnn_accelerator_execute_time_us',
                'unit': 'microseconds',
                'type': 'timing'
            },
            'RPC (execute) time': {
                'key': 'rpc_execute_time_us',
                'unit': 'microseconds',
                'type': 'timing'
            },
            'QNN (finalize) time': {
                'key': 'qnn_finalize_time_us',
                'unit': 'microseconds',
                'type': 'timing'
            },
            'Accelerator (finalize) time': {
                'key': 'accelerator_finalize_time_us',
                'unit': 'microseconds',
                'type': 'timing'
            },
            'QNN accelerator (finalize) time': {
                'key': 'qnn_accelerator_finalize_time_us',
                'unit': 'microseconds',
                'type': 'timing'
            },
            'RPC (finalize) time': {
                'key': 'rpc_finalize_time_us',
                'unit': 'microseconds',
                'type': 'timing'
            },
            'duration': {
                'key': 'duration_us',
                'unit': 'microseconds',
                'type': 'timing'
            },
            'numInferences': {
                'key': 'num_inferences',
                'unit': 'count',
                'type': 'counter'
            },
            'Number of HVX threads used': {
                'key': 'hvx_threads_used',
                'unit': 'count',
                'type': 'counter'
            }
        }

    def extract_strings_and_positions(self, data: bytes) -> Dict[str, List[int]]:
        """
        Extract ASCII strings and all their positions in binary data
        
        Args:
            data: Binary data from QNN log file
            
        Returns:
            Dictionary mapping string -> list of positions
        """
        strings_positions = {}
        current_string = ""
        start_pos = 0
        
        for i, byte in enumerate(data):
            if 32 <= byte <= 126:  # Printable ASCII
                if not current_string:
                    start_pos = i
                current_string += chr(byte)
            else:
                if len(current_string) >= 3:
                    if current_string not in strings_positions:
                        strings_positions[current_string] = []
                    strings_positions[current_string].append(start_pos)
                current_string = ""
        
        # Handle final string
        if len(current_string) >= 3:
            if current_string not in strings_positions:
                strings_positions[current_string] = []
            strings_positions[current_string].append(start_pos)
            
        return strings_positions

    def extract_value_at_offset(self, data: bytes, position: int, offset: int) -> Optional[int]:
        """
        Extract 32-bit little-endian value at specific offset from position
        
        Args:
            data: Binary data
            position: Base position (string start)
            offset: Offset from position (can be negative)
            
        Returns:
            Extracted value or None if invalid
        """
        try:
            value_pos = position + offset
            if 0 <= value_pos <= len(data) - 4:
                value = struct.unpack('<I', data[value_pos:value_pos + 4])[0]
                return value
        except (struct.error, IndexError):
            pass
        return None

    def extract_metric_value(self, data: bytes, string_positions: List[int], pattern_info: Dict) -> Tuple[Optional[int], int]:
        """
        Extract metric value by searching around all string positions
        
        Args:
            data: Binary data
            string_positions: List of positions where the string occurs
            pattern_info: Pattern configuration
            
        Returns:
            Tuple of (value, offset_used) or (None, -1)
        """
        pattern_type = pattern_info['type']
        
        # Define search offsets based on pattern analysis
        search_offsets = [
            # Common positive offsets
            16, 20, 28, 36, 40, 52, 56, 64,
            # Common negative offsets  
            -12, -16, -20, -28, -36, -40, -52, -56, -64, -68, -72, -76, -80, -84, -88, -92, -96, -100,
            # Additional offsets for edge cases
            8, 12, 24, 32, 44, 48, 60, 68, 72, 76, 80, 84, 88, 92, 96, 100
        ]
        
        # Try each string position
        for string_pos in string_positions:
            # Try each offset
            for offset in search_offsets:
                value = self.extract_value_at_offset(data, string_pos, offset)
                if value is not None:
                    # Apply basic validation
                    if pattern_type == 'counter':
                        # For counters, check they're not absurdly large
                        if value > 1000000:  # 1 million max for any counter
                            continue
                    elif pattern_type == 'timing':
                        # For timing, allow a wide range
                        if value > 10000000:  # 10 seconds max timing value
                            continue
                    
                    return value, offset
        
        return None, -1

    def parse_file(self, file_path: str) -> Dict[str, Any]:
        """
        Parse QNN profiling file and extract all metrics
        
        Args:
            file_path: Path to QNN profiling log file
            
        Returns:
            Dictionary with parsed metrics and metadata
        """
        
        with open(file_path, 'rb') as f:
            data = f.read()
        
        # Extract strings and all their positions
        strings_positions = self.extract_strings_and_positions(data)
        
        # Initialize results
        results = {
            'file_info': {
                'path': file_path,
                'size_bytes': len(data),
                'backend_version': '',
                'graph_name': ''
            },
            'extraction_info': {
                'strings_found': len(strings_positions),
                'metrics_extracted': 0,
                'failed_extractions': []
            },
            'metrics': {},
            'raw_extraction_details': []
        }
        
        # Extract version and graph info
        for string_val, positions in strings_positions.items():
            if 'v2.35.0' in string_val:
                results['file_info']['backend_version'] = string_val
            elif '_quantized_htp' in string_val or '_quantized_cpu' in string_val or '_quantized_gpu' in string_val:
                results['file_info']['graph_name'] = string_val
        
        # Extract metrics
        extracted_count = 0
        
        for pattern_name, pattern_info in self.metric_patterns.items():
            if pattern_name in strings_positions:
                positions = strings_positions[pattern_name]
                value, offset_used = self.extract_metric_value(data, positions, pattern_info)
                
                if value is not None:
                    key = pattern_info['key']
                    results['metrics'][key] = value
                    extracted_count += 1
                    
                    # Store extraction details (using first position for reporting)
                    results['raw_extraction_details'].append({
                        'pattern': pattern_name,
                        'key': key,
                        'value': value,
                        'string_position': f"0x{positions[0]:04x}",
                        'offset_used': offset_used,
                        'extraction_position': f"0x{positions[0] + offset_used:04x}",
                        'unit': pattern_info['unit'],
                        'type': pattern_info['type']
                    })
                else:
                    results['extraction_info']['failed_extractions'].append(pattern_name)
        
        results['extraction_info']['metrics_extracted'] = extracted_count
        
        return results

    def calculate_derived_metrics(self, metrics: Dict[str, int]) -> Dict[str, Any]:
        """
        Calculate derived performance metrics from extracted data
        
        Args:
            metrics: Dictionary of extracted metrics
            
        Returns:
            Dictionary of derived metrics
        """
        derived = {}
        
        # Primary execution time
        if 'qnn_execute_time_us' in metrics:
            derived['primary_execution_time_us'] = metrics['qnn_execute_time_us']
        elif 'accelerator_execute_time_us' in metrics:
            derived['primary_execution_time_us'] = metrics['accelerator_execute_time_us']
        
        # Throughput calculations
        if 'primary_execution_time_us' in derived and 'num_inferences' in metrics:
            exec_time = derived['primary_execution_time_us']
            num_inf = metrics['num_inferences']
            if exec_time > 0 and num_inf > 0:
                derived['throughput_inferences_per_second'] = (1000000 * num_inf) / exec_time
                derived['avg_time_per_inference_us'] = exec_time / num_inf
        
        # Component timing analysis
        execution_times = []
        finalize_times = []
        deinit_times = []
        
        for key, value in metrics.items():
            if 'execute' in key and 'time_us' in key:
                execution_times.append(value)
            elif 'finalize' in key and 'time_us' in key:
                finalize_times.append(value)
            elif 'deinit' in key and 'time_us' in key:
                deinit_times.append(value)
        
        if execution_times:
            derived['total_execution_time_us'] = sum(execution_times)
            derived['avg_execution_time_us'] = sum(execution_times) / len(execution_times)
        
        if finalize_times:
            derived['total_finalize_time_us'] = sum(finalize_times)
            derived['avg_finalize_time_us'] = sum(finalize_times) / len(finalize_times)
        
        if deinit_times:
            derived['total_deinit_time_us'] = sum(deinit_times)
            derived['avg_deinit_time_us'] = sum(deinit_times) / len(deinit_times)
        
        # Efficiency calculations
        if ('accelerator_execute_time_us' in metrics and 
            'qnn_execute_time_us' in metrics and
            metrics['qnn_execute_time_us'] > 0):
            efficiency = (metrics['accelerator_execute_time_us'] / metrics['qnn_execute_time_us']) * 100
            derived['accelerator_efficiency_percent'] = efficiency
        
        # RPC overhead analysis
        if ('rpc_execute_time_us' in metrics and 
            'accelerator_execute_time_us' in metrics and
            metrics['accelerator_execute_time_us'] > 0):
            overhead_ratio = metrics['rpc_execute_time_us'] / metrics['accelerator_execute_time_us']
            derived['rpc_overhead_ratio'] = overhead_ratio
        
        return derived

def format_consistent_output(results: Dict[str, Any], include_derived: bool = True) -> None:
    """
    Format output in consistent format for script usage
    Format: METRIC_FLAG: key = value unit [details]
    """
    
    print("QNN_PROFILING_PARSE_RESULTS")
    print("=" * 60)
    
    # File information
    file_info = results['file_info']
    print(f"FILE_INFO: path = {file_info['path']}")
    print(f"FILE_INFO: size_bytes = {file_info['size_bytes']}")
    print(f"FILE_INFO: backend_version = {file_info.get('backend_version', 'unknown')}")
    print(f"FILE_INFO: graph_name = {file_info.get('graph_name', 'unknown')}")
    
    # Extraction statistics
    extract_info = results['extraction_info']
    print(f"EXTRACT_INFO: strings_found = {extract_info['strings_found']}")
    print(f"EXTRACT_INFO: metrics_extracted = {extract_info['metrics_extracted']}")
    print(f"EXTRACT_INFO: failed_extractions = {len(extract_info['failed_extractions'])}")
    
    print()
    
    # Raw metrics in consistent format
    metrics = results['metrics']
    if metrics:
        print("EXTRACTED_METRICS:")
        print("-" * 30)
        
        # Sort by category for consistent ordering
        timing_metrics = []
        counter_metrics = []
        
        for detail in results['raw_extraction_details']:
            if detail['type'] == 'timing':
                timing_metrics.append(detail)
            else:
                counter_metrics.append(detail)
        
        # Output timing metrics
        for detail in sorted(timing_metrics, key=lambda x: x['key']):
            key = detail['key']
            value = detail['value']
            unit = detail['unit']
            offset = detail['offset_used']
            print(f"TIMING_METRIC: {key} = {value} {unit} [offset={offset:+d}]")
        
        # Output counter metrics
        for detail in sorted(counter_metrics, key=lambda x: x['key']):
            key = detail['key']
            value = detail['value']
            unit = detail['unit']
            offset = detail['offset_used']
            print(f"COUNTER_METRIC: {key} = {value} {unit} [offset={offset:+d}]")
    
    # Derived metrics
    if include_derived and metrics:
        derived = QNNLogParser().calculate_derived_metrics(metrics)
        if derived:
            print()
            print("DERIVED_METRICS:")
            print("-" * 20)
            
            for key, value in sorted(derived.items()):
                if isinstance(value, float):
                    print(f"DERIVED_METRIC: {key} = {value:.3f}")
                else:
                    print(f"DERIVED_METRIC: {key} = {value}")
    
    # Failed extractions
    if extract_info['failed_extractions']:
        print()
        print("FAILED_EXTRACTIONS:")
        print("-" * 25)
        for failed in extract_info['failed_extractions']:
            print(f"FAILED_EXTRACTION: {failed}")

def format_json_output(results: Dict[str, Any], include_derived: bool = True) -> None:
    """Output results in JSON format"""
    if include_derived and results['metrics']:
        derived = QNNLogParser().calculate_derived_metrics(results['metrics'])
        results['derived_metrics'] = derived
    
    print(json.dumps(results, indent=2))

def format_csv_output(results: Dict[str, Any], include_derived: bool = True) -> None:
    """Output results in CSV format"""
    all_metrics = results['metrics'].copy()
    
    if include_derived and results['metrics']:
        derived = QNNLogParser().calculate_derived_metrics(results['metrics'])
        all_metrics.update(derived)
    
    if all_metrics:
        # Header
        headers = sorted(all_metrics.keys())
        print(','.join(headers))
        
        # Values
        values = [str(all_metrics.get(h, '')) for h in headers]
        print(','.join(values))

def main():
    parser = argparse.ArgumentParser(description='QNN Log Parser')
    parser.add_argument('file', help='Path to QNN profiling log file')
    parser.add_argument('--json', action='store_true', help='Output in JSON format')
    parser.add_argument('--csv', action='store_true', help='Output in CSV format')
    parser.add_argument('--no-derived', action='store_true', help='Skip derived metrics calculation')
    parser.add_argument('--raw-details', action='store_true', help='Show raw extraction details')
    
    args = parser.parse_args()
    
    if not Path(args.file).exists():
        print(f"ERROR: File {args.file} does not exist", file=sys.stderr)
        return 1
    
    # Parse the file
    qnn_parser = QNNLogParser()
    results = qnn_parser.parse_file(args.file)
    
    include_derived = not args.no_derived
    
    # Output in requested format
    if args.json:
        format_json_output(results, include_derived)
    elif args.csv:
        format_csv_output(results, include_derived)
    else:
        format_consistent_output(results, include_derived)
        
        if args.raw_details:
            print()
            print("RAW_EXTRACTION_DETAILS:")
            print("-" * 30)
            for detail in results['raw_extraction_details']:
                print(f"DETAIL: pattern='{detail['pattern']}' key={detail['key']} value={detail['value']} "
                      f"string_pos={detail['string_position']} offset={detail['offset_used']:+d} "
                      f"extract_pos={detail['extraction_position']} type={detail['type']}")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
