//
//  Shaders.metal
//  BatteryDrain
//
//  Created by Ryan Plitt on 5/9/25.
//

#include <metal_stdlib>
using namespace metal;

// Enhanced shader for maximum GPU thermal stress
kernel void heavyCompute(device float *buf [[ buffer(0) ]],
                         uint2 gid        [[ thread_position_in_grid ]]) {
    // Much more intensive calculation to maximize GPU load:
    float x = float(gid.x) / 4096.0;
    float y = float(gid.y) / 4096.0;
    
    // Multiple complex operations to stress the GPU - enhanced intensity
    float result = 0.0;
    for (int i = 0; i < 100; i++) { // Doubled iterations for maximum stress
        float iter = float(i) * 0.1;
        result += sin(x * 100.0 + iter) * cos(y * 100.0 + iter);
        result += pow(x + iter, 2.5) * sqrt(y + iter + 1.0);
        result += exp(x * 0.1 + iter) * log(y + iter + 1.0);
        result += atan2(x + iter, y + iter);
        
        // Additional intensive operations
        result += tan(x * 50.0 + iter) * asin(clamp(y + iter, -1.0, 1.0));
        result += cosh(x + iter) * sinh(y + iter);
        result += pow(abs(x + iter), 3.0) * pow(abs(y + iter), 2.0);
        
        // Complex trigonometric combinations
        float angle = x * 200.0 + y * 200.0 + iter;
        result += sin(angle) * cos(angle * 2.0) * tan(angle * 0.5);
        
        // Additional matrix operations for maximum ALU stress
        float4x4 matrix = float4x4(
            float4(sin(iter), cos(iter), tan(iter), 1.0),
            float4(cos(iter), sin(iter * 2), cos(iter * 3), 1.0),
            float4(tan(iter), sin(iter / 2), cos(iter / 3), 1.0),
            float4(1.0, 1.0, 1.0, 1.0)
        );
        
        float4 vector = float4(x + iter, y + iter, result, 1.0);
        vector = matrix * vector;
        result += vector.x + vector.y + vector.z;
        
        // Memory stress operations
        if (i % 10 == 0) {
            uint bufferIndex = (gid.x + gid.y * 4096 + i) % (4096 * 4096);
            result += buf[bufferIndex] * 0.001;
        }
    }
    
    // Additional post-processing to increase GPU load
    result = fmod(result, 1000.0); // Keep result manageable
    result = sqrt(abs(result)) + sin(result) + cos(result);
    
    // Additional complex operations for maximum thermal generation
    result = pow(result, 1.5) + atan(result) + sinh(result * 0.01);
    
    buf[gid.x + gid.y * 4096] = result;
}

// Additional compute kernel for simultaneous GPU stress
kernel void thermalStressKernel(device float *data [[ buffer(0) ]],
                               uint index [[ thread_position_in_grid ]]) {
    // Maximum thermal stress operations running in parallel
    float value = data[index];
    
    // Intensive floating point operations
    for (int i = 0; i < 10000; i++) {
        value = sin(value) * cos(value) + sqrt(abs(value));
        value = pow(value, 2.1) + log(abs(value) + 1.0);
        value = fma(value, 3.14159, 2.71828);
        value = exp(value * 0.001) + tan(value * 0.1);
    }
    
    // Memory intensive operations for additional stress
    for (int j = 0; j < 1000; j++) {
        uint memIndex = (index + j) % 1000000;
        float temp = data[memIndex];
        value = temp * value + float(j);
    }
    
    data[index] = value;
}
