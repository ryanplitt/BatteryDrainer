//
//  Shaders.metal
//  BatteryDrain
//
//  Created by Ryan Plitt on 5/9/25.
//

#include <metal_stdlib>
using namespace metal;

// This buffer is implicitly created for us by MTKView,
// but we never actually allocate or bind it—Metal will give
// us one automatically large enough to cover the dispatch.
kernel void heavyCompute(device float *buf [[ buffer(0) ]],
                         uint2 gid        [[ thread_position_in_grid ]]) {
    // Much more intensive calculation to maximize GPU load:
    float x = float(gid.x) / 4096.0;
    float y = float(gid.y) / 4096.0;
    
    // Multiple complex operations to stress the GPU
    float result = 0.0;
    for (int i = 0; i < 50; i++) {
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
    }
    
    // Additional post-processing to increase GPU load
    result = fmod(result, 1000.0); // Keep result manageable
    result = sqrt(abs(result)) + sin(result) + cos(result);
    
    buf[gid.x + gid.y * 4096] = result;
}
