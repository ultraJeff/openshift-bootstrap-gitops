#!/usr/bin/env python3
"""
Simple memory-consuming application for testing OpenShift resource limits.
Allocates 2GB of memory and provides health endpoints.
"""

import os
import time
import logging
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

# Global variable to hold memory
memory_consumer = []
TARGET_MEMORY_GB = 2
TARGET_MEMORY_BYTES = TARGET_MEMORY_GB * 1024 * 1024 * 1024

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

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "timestamp": time.time(),
        "memory_stats": get_memory_stats()
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
        "memory_stats": get_memory_stats()
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
        "memory_stats": get_memory_stats()
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
        "memory_stats": get_memory_stats()
    })

@app.route('/')
def root():
    """Root endpoint with application info"""
    return jsonify({
        "app": "memory-test-app",
        "version": "1.1.0",
        "description": f"Memory testing application - Max: {TARGET_MEMORY_GB}GB",
        "endpoints": {
            "/health": "Health check",
            "/ready": "Readiness probe", 
            "/memory": "Memory statistics",
            "/allocate": "Trigger memory allocation (default 2GB)",
            "/allocate?mb=X": "Allocate X MB of memory",
            "/allocate/<mb>": "Allocate specific MB via path (e.g., /allocate/500)",
            "/release": "Release allocated memory"
        },
        "usage_examples": {
            "allocate_default": "/allocate (allocates 2GB)",
            "allocate_query": "/allocate?mb=500 (allocates 500MB)",
            "allocate_path": "/allocate/1024 (allocates 1GB)",
            "memory_stats": "/memory (current usage)"
        },
        "limits": {
            "min_mb": 10,
            "max_mb": 2048,
            "container_limit": "2Gi"
        },
        "memory_stats": get_memory_stats()
    })

if __name__ == '__main__':
    logger.info("Starting Memory Test Application")
    logger.info(f"Target memory allocation: {TARGET_MEMORY_GB}GB")
    
    # Don't allocate memory on startup by default
    logger.info("Application started. Use /allocate endpoints to trigger memory allocation.")
    
    # Start Flask app
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)