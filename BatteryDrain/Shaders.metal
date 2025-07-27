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
    }
    
    buf[gid.x + gid.y * 4096] = result;
}
