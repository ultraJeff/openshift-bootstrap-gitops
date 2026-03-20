#!/usr/bin/env python3
"""
Resource testing application for OpenShift memory and CPU limits.
Provides endpoints for memory allocation and CPU stress testing.
"""

import os
import time
import logging
import threading
import multiprocessing
from flask import Flask, jsonify, request
import psutil
import gc

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Global variables for resource testing
memory_consumer = []
cpu_stress_threads = []
cpu_stress_active = False

TARGET_MEMORY_GB = 2
TARGET_MEMORY_BYTES = TARGET_MEMORY_GB * 1024 * 1024 * 1024
CPU_COUNT = multiprocessing.cpu_count()

def allocate_memory(target_mb=None):
    """Allocate specified amount of memory in MB"""
    if target_mb is None:
        target_mb = TARGET_MEMORY_GB * 1024  # Default to 2GB

    # Safety limits
    MAX_ALLOCATION_MB = 2048  # 2GB max to respect container limits
    MIN_ALLOCATION_MB = 10    # 10MB minimum

    target_mb = max(MIN_ALLOCATION_MB, min(target_mb, MAX_ALLOCATION_MB))

    try:
        logger.info(f"Starting memory allocation - Target: {target_mb}MB")

        # Clear any existing allocations
        global memory_consumer
        memory_consumer.clear()
        gc.collect()

        # Allocate memory in chunks
        chunk_size = 10 * 1024 * 1024  # 10MB chunks
        target_bytes = target_mb * 1024 * 1024
        chunks_needed = target_bytes // chunk_size

        for i in range(int(chunks_needed)):
            # Create a chunk filled with data
            chunk = bytearray(chunk_size)
            # Fill with some data to ensure it's actually allocated
            for j in range(0, chunk_size, 1024):
                chunk[j:j+8] = b'TESTDATA'

            memory_consumer.append(chunk)

            # Log progress every 100MB
            if (i + 1) % 10 == 0:
                allocated_mb = (i + 1) * chunk_size / (1024 * 1024)
                logger.info(f"Allocated: {allocated_mb:.0f}MB")

        # Handle remaining bytes for partial chunks
        remaining_bytes = target_bytes % chunk_size
        if remaining_bytes > 0:
            chunk = bytearray(remaining_bytes)
            for j in range(0, remaining_bytes, 1024):
                end_idx = min(j + 8, remaining_bytes)
                chunk[j:end_idx] = b'TESTDATA'[:end_idx-j]
            memory_consumer.append(chunk)

        # Get actual memory usage
        process = psutil.Process()
        memory_info = process.memory_info()
        memory_mb = memory_info.rss / 1024 / 1024

        logger.info(f"Memory allocation complete. Target: {target_mb}MB, RSS: {memory_mb:.2f}MB")
        return True, target_mb

    except Exception as e:
        logger.error(f"Memory allocation failed: {e}")
        return False, target_mb

def cpu_stress_worker(duration, intensity=1.0):
    """CPU stress testing worker function"""
    global cpu_stress_active
    end_time = time.time() + duration

    logger.info(f"Starting CPU stress worker for {duration}s at {intensity*100}% intensity")

    while time.time() < end_time and cpu_stress_active:
        # High CPU computation
        for _ in range(int(10000 * intensity)):
            _ = sum(x * x for x in range(100))

        # Brief pause based on intensity (lower intensity = more pauses)
        if intensity < 1.0:
            time.sleep(0.001 * (1 - intensity))

    logger.info("CPU stress worker finished")

def start_cpu_stress(threads=None, duration=30, intensity=1.0):
    """Start CPU stress testing"""
    global cpu_stress_threads, cpu_stress_active

    # Stop any existing CPU stress
    stop_cpu_stress()

    if threads is None:
        threads = CPU_COUNT

    # Limit threads to available CPU cores
    threads = min(threads, CPU_COUNT)
    threads = max(1, threads)  # At least 1 thread

    # Limit duration and intensity for safety
    duration = min(duration, 300)  # Max 5 minutes
    duration = max(1, duration)     # Min 1 second
    intensity = min(intensity, 1.0) # Max 100%
    intensity = max(0.1, intensity) # Min 10%

    logger.info(f"Starting CPU stress test: {threads} threads, {duration}s duration, {intensity*100}% intensity")

    cpu_stress_active = True
    cpu_stress_threads = []

    for i in range(threads):
        thread = threading.Thread(target=cpu_stress_worker, args=(duration, intensity))
        thread.daemon = True
        thread.start()
        cpu_stress_threads.append(thread)

    return True, threads, duration, intensity

def stop_cpu_stress():
    """Stop CPU stress testing"""
    global cpu_stress_active, cpu_stress_threads

    logger.info("Stopping CPU stress test")
    cpu_stress_active = False

    # Wait for threads to finish (they should stop quickly)
    for thread in cpu_stress_threads:
        if thread.is_alive():
            thread.join(timeout=2)

    active_threads = sum(1 for t in cpu_stress_threads if t.is_alive())
    cpu_stress_threads = []

    return active_threads == 0

def get_cpu_stats():
    """Get current CPU statistics"""
    try:
        process = psutil.Process()
        cpu_percent = process.cpu_percent(interval=0.1)

        return {
            "cpu_percent": round(cpu_percent, 2),
            "cpu_count": CPU_COUNT,
            "stress_active": cpu_stress_active,
            "active_stress_threads": len([t for t in cpu_stress_threads if t.is_alive()]),
            "total_stress_threads": len(cpu_stress_threads)
        }
    except Exception as e:
        logger.error(f"Error getting CPU stats: {e}")
        return {"error": str(e)}

def get_memory_stats():
    """Get current memory statistics"""
    try:
        process = psutil.Process()
        memory_info = process.memory_info()

        return {
            "rss_mb": round(memory_info.rss / 1024 / 1024, 2),
            "vms_mb": round(memory_info.vms / 1024 / 1024, 2),
            "percent": round(process.memory_percent(), 2),
            "allocated_chunks": len(memory_consumer),
            "target_gb": TARGET_MEMORY_GB
        }
    except Exception as e:
        logger.error(f"Error getting memory stats: {e}")
        return {"error": str(e)}

def get_resource_stats():
    """Get combined memory and CPU statistics"""
    return {
        "memory": get_memory_stats(),
        "cpu": get_cpu_stats()
    }

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "timestamp": time.time(),
        "resource_stats": get_resource_stats()
    })

@app.route('/ready')
def ready():
    """Readiness probe endpoint"""
    return jsonify({
        "status": "ready",
        "memory_allocated": len(memory_consumer) > 0
    })

@app.route('/memory')
def memory_info():
    """Detailed memory information endpoint"""
    return jsonify(get_memory_stats())

@app.route('/cpu')
def cpu_info():
    """Detailed CPU information endpoint"""
    return jsonify(get_cpu_stats())

@app.route('/resources')
def resource_info():
    """Combined resource information endpoint"""
    return jsonify(get_resource_stats())

@app.route('/allocate')
def allocate():
    """Endpoint to trigger memory allocation with optional MB parameter"""
    # Get target MB from query parameter, default to 2GB
    target_mb = request.args.get('mb', type=int)
    if target_mb is None:
        target_mb = TARGET_MEMORY_GB * 1024  # 2GB default

    success, actual_target = allocate_memory(target_mb)
    return jsonify({
        "success": success,
        "message": f"Memory allocation " + ("completed" if success else "failed"),
        "requested_mb": target_mb,
        "allocated_mb": actual_target if success else 0,
        "resource_stats": get_resource_stats()
    })

@app.route('/allocate/<int:mb>')
def allocate_specific(mb):
    """Endpoint to allocate specific amount of memory in MB via path"""
    success, actual_target = allocate_memory(mb)
    return jsonify({
        "success": success,
        "message": f"Memory allocation " + ("completed" if success else "failed"),
        "requested_mb": mb,
        "allocated_mb": actual_target if success else 0,
        "resource_stats": get_resource_stats()
    })

@app.route('/release')
def release():
    """Endpoint to release allocated memory"""
    global memory_consumer
    chunks_released = len(memory_consumer)
    memory_consumer.clear()
    gc.collect()

    logger.info(f"Released {chunks_released} memory chunks")

    return jsonify({
        "success": True,
        "chunks_released": chunks_released,
        "resource_stats": get_resource_stats()
    })

@app.route('/cpu/stress')
def cpu_stress():
    """Start CPU stress test with optional parameters"""
    # Get parameters from query string
    threads = request.args.get('threads', type=int)
    duration = request.args.get('duration', default=30, type=int)
    intensity = request.args.get('intensity', default=1.0, type=float)

    success, actual_threads, actual_duration, actual_intensity = start_cpu_stress(threads, duration, intensity)

    return jsonify({
        "success": success,
        "message": f"CPU stress test " + ("started" if success else "failed"),
        "requested": {
            "threads": threads,
            "duration": duration,
            "intensity": intensity
        },
        "actual": {
            "threads": actual_threads,
            "duration": actual_duration,
            "intensity": actual_intensity
        },
        "resource_stats": get_resource_stats()
    })

@app.route('/cpu/stress/<int:threads>')
def cpu_stress_specific(threads):
    """Start CPU stress test with specific thread count"""
    duration = request.args.get('duration', default=30, type=int)
    intensity = request.args.get('intensity', default=1.0, type=float)

    success, actual_threads, actual_duration, actual_intensity = start_cpu_stress(threads, duration, intensity)

    return jsonify({
        "success": success,
        "message": f"CPU stress test " + ("started" if success else "failed"),
        "requested": {
            "threads": threads,
            "duration": duration,
            "intensity": intensity
        },
        "actual": {
            "threads": actual_threads,
            "duration": actual_duration,
            "intensity": actual_intensity
        },
        "resource_stats": get_resource_stats()
    })

@app.route('/cpu/stop')
def cpu_stop():
    """Stop CPU stress testing"""
    success = stop_cpu_stress()

    return jsonify({
        "success": success,
        "message": "CPU stress test " + ("stopped" if success else "failed to stop completely"),
        "resource_stats": get_resource_stats()
    })

@app.route('/')
def root():
    """Root endpoint with application info"""
    return jsonify({
        "app": "resource-test-app",
        "version": "2.0.0",
        "description": f"Memory and CPU testing application for OpenShift resource limits",
        "capabilities": {
            "memory_testing": f"Up to {TARGET_MEMORY_GB}GB allocation",
            "cpu_testing": f"Up to {CPU_COUNT} thread stress testing"
        },
        "endpoints": {
            "/health": "Health check with resource stats",
            "/ready": "Readiness probe",
            "/memory": "Memory statistics only",
            "/cpu": "CPU statistics only",
            "/resources": "Combined memory and CPU statistics",
            "/allocate": "Memory allocation (default 2GB)",
            "/allocate?mb=X": "Allocate X MB of memory",
            "/allocate/<mb>": "Allocate specific MB via path",
            "/release": "Release allocated memory",
            "/cpu/stress": "Start CPU stress test",
            "/cpu/stress?threads=X&duration=Y&intensity=Z": "CPU stress with params",
            "/cpu/stress/<threads>": "CPU stress with specific thread count",
            "/cpu/stop": "Stop CPU stress test"
        },
        "usage_examples": {
            "memory_allocate_default": "/allocate (allocates 2GB)",
            "memory_allocate_query": "/allocate?mb=500 (allocates 500MB)",
            "memory_allocate_path": "/allocate/1024 (allocates 1GB)",
            "cpu_stress_default": "/cpu/stress (30s, all cores, 100% intensity)",
            "cpu_stress_custom": "/cpu/stress?threads=2&duration=60&intensity=0.5",
            "cpu_stress_path": "/cpu/stress/4 (4 threads, 30s, 100% intensity)",
            "resource_stats": "/resources (combined stats)"
        },
        "limits": {
            "memory_min_mb": 10,
            "memory_max_mb": 2048,
            "cpu_max_threads": CPU_COUNT,
            "cpu_max_duration_sec": 300,
            "container_limits": "2Gi memory, 1 CPU core"
        },
        "resource_stats": get_resource_stats()
    })

if __name__ == '__main__':
    logger.info("Starting Resource Test Application v2.0.0")
    logger.info(f"Memory testing: Up to {TARGET_MEMORY_GB}GB allocation")
    logger.info(f"CPU testing: Up to {CPU_COUNT} threads stress testing")

    # Don't allocate resources on startup by default
    logger.info("Application started. Use /allocate endpoints for memory testing and /cpu/stress for CPU testing.")

    # Start Flask app
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
