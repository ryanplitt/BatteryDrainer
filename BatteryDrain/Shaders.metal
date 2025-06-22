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
    // A simple “plasma” calculation to keep ALUs busy:
    float x = float(gid.x) / 4096.0;
    float y = float(gid.y) / 4096.0;
    buf[gid.x + gid.y * 4096] = sin(x * 100.0) * cos(y * 100.0);
}
