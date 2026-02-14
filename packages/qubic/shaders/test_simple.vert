#version 450

// Push constant for MVP matrix (required but we'll ignore it for testing)
layout(push_constant) uniform PushConstants {
    mat4 mvp;
} pc;

// Vertex input from vertex buffer
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inColor;

// Output to fragment shader
layout(location = 0) out vec3 fragColor;

void main() {
    // Draw vertices directly in NDC space (ignore MVP for testing)
    // Scale down and offset to fit in view
    gl_Position = vec4(inPosition.x * 0.5, inPosition.y * 0.5, 0.5, 1.0);
    fragColor = inColor;
}
