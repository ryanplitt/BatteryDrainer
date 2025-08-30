# WebSocket Server Setup for BatteryDrainer Aggressive Mode

## Overview

The BatteryDrainer app uses WebSocket connections **only in aggressive mode** to create continuous high-frequency data streaming that maximizes network interface utilization and battery drain. This document outlines what the WebSocket implementation does and how to set up a compatible server.

## WebSocket Purpose and Functionality

### Client-Side Behavior
- **6 simultaneous WebSocket connections** established when aggressive mode is enabled
- **High-frequency streaming**: 20 messages per second per connection (120 messages/sec total)
- **10KB message size**: Each message contains 10,000 bytes of random data
- **Bidirectional communication**: Client sends data and expects echo/response to maintain active connection
- **Continuous operation**: Runs until network operations are stopped

### Battery Drain Impact
- **Persistent connections** prevent network interface from entering low-power states
- **High-frequency transmission** maximizes radio active time
- **Large data volumes** stress network buffers and processing
- **Multiple concurrent streams** amplify power consumption

## Server Requirements

### Basic WebSocket Echo Server
The simplest implementation is a WebSocket echo server that receives messages and sends them back:

```javascript
// Node.js WebSocket Echo Server Example
const WebSocket = require('ws');

const wss = new WebSocket.Server({ port: 8080 });

wss.on('connection', function connection(ws) {
    console.log('New WebSocket connection established');
    
    ws.on('message', function incoming(data) {
        console.log('Received:', data.length, 'bytes');
        // Echo the data back to maintain connection
        ws.send(data);
    });
    
    ws.on('close', function close() {
        console.log('WebSocket connection closed');
    });
    
    ws.on('error', function error(err) {
        console.error('WebSocket error:', err);
    });
});

console.log('WebSocket server listening on port 8080');
```

### Server Configuration

#### Network Settings
- **Port**: Any available port (default suggestion: 8080)
- **Protocol**: WebSocket (ws://) or Secure WebSocket (wss://)
- **Binding**: Listen on all interfaces (0.0.0.0) for maximum compatibility
- **Buffer sizes**: Configure for high throughput (10KB+ message handling)

#### Performance Recommendations
- **Keep-alive**: Enable TCP keep-alive for persistent connections
- **Buffer management**: Handle rapid message arrival (20/sec per connection)
- **Connection limits**: Support 6+ simultaneous connections per device
- **Memory management**: Efficiently handle continuous 10KB message processing

### Server URL Configuration

Update the client WebSocket URL in `BatteryDrainer.swift` line 729:

```swift
// Replace this line:
guard let url = URL(string: "wss://echo.websocket.org") else { continue }

// With your server URL:
guard let url = URL(string: "ws://YOUR_SERVER_IP:YOUR_PORT") else { continue }
```

### Example Server URLs
- Local network: `ws://192.168.1.100:8080`
- External server: `ws://your-domain.com:8080`
- Secure connection: `wss://your-domain.com:443`

## Advanced Server Features (Optional)

### Enhanced Data Processing
For maximum battery drain, the server can implement additional processing:

```javascript
ws.on('message', function incoming(data) {
    // Process received data to create server load
    const processed = processData(data);
    
    // Send back modified data to increase complexity
    const response = generateResponse(processed);
    ws.send(response);
    
    // Optional: Send additional unsolicited data
    setTimeout(() => {
        ws.send(generateAdditionalData());
    }, 25); // Send extra data between client messages
});
```

### Multiple Message Types
Implement different message handlers for varied network patterns:

```javascript
ws.on('message', function incoming(data) {
    try {
        const message = JSON.parse(data);
        
        switch (message.type) {
            case 'ping':
                ws.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
                break;
            case 'data':
                // Echo back with additional processing
                ws.send(JSON.stringify({ 
                    type: 'response', 
                    original: message.data,
                    processed: performHeavyProcessing(message.data)
                }));
                break;
        }
    } catch {
        // Handle binary data - echo back as-is
        ws.send(data);
    }
});
```

## Deployment Options

### Local Testing Server
- Run server on local machine or local network device
- Use IP address of the server machine
- Ensure firewall allows connections on chosen port

### Cloud Deployment
- Deploy to AWS, Google Cloud, Azure, or similar
- Use public IP or domain name
- Configure security groups/firewall for WebSocket port
- Consider using wss:// with SSL certificate for secure connections

### Docker Container
```dockerfile
FROM node:16
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 8080
CMD ["node", "websocket-server.js"]
```

## Testing the Server

### Connection Test
1. Start your WebSocket server
2. Enable aggressive mode in BatteryDrainer app
3. Start network operations
4. Check server logs for incoming connections and messages

### Performance Validation
Monitor server for:
- 6 simultaneous connections per device
- ~120 messages per second total throughput
- 10KB average message size
- Continuous bidirectional data flow

## Integration with BatteryDrainer

### Current Implementation
- WebSocket streaming starts automatically with `startNetworkRequests()` in aggressive mode
- Runs alongside concurrent download and upload operations
- Stops when `stopUploadRequests()` is called
- No WebSocket activity in regular mode (preserves original behavior)

### Error Handling
- Connection failures are logged but don't stop other network operations
- Automatic cleanup when network operations stop
- Graceful degradation if server is unavailable

## Security Considerations

### For Testing Environment
- Use unencrypted WebSocket (ws://) for local testing
- No authentication required for battery drain testing
- Focus on throughput over security

### For Production/Secure Environment
- Use secure WebSocket (wss://) with SSL certificates
- Implement basic authentication if needed
- Consider rate limiting if server resources are limited

## Server Performance Impact

Running this WebSocket server will:
- Generate significant server network traffic
- Require processing power for message handling
- Use memory for connection management
- Benefit from SSD storage for optimal performance

The server essentially acts as a network traffic amplifier, receiving the continuous high-frequency data from the iOS device and responding appropriately to maintain maximum network utilization and battery drain.