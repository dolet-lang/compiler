/*
 * Dolet Minimal Runtime for Embedded/Bare-Metal Systems
 * No OS dependencies - direct hardware access
 */

#include <stdint.h>
#include <stddef.h>

/* ============================================================================
 * Configuration - Customize for your hardware
 * ============================================================================ */

// UART base address (example for ARM Cortex-M)
#define UART_BASE 0x40011000
#define UART_DR   (*(volatile uint32_t*)(UART_BASE + 0x00))
#define UART_SR   (*(volatile uint32_t*)(UART_BASE + 0x04))

// Heap configuration
#define HEAP_SIZE (64 * 1024)  // 64KB heap
static uint8_t heap_memory[HEAP_SIZE];
static size_t heap_offset = 0;

/* ============================================================================
 * Minimal Memory Allocator (bump allocator)
 * ============================================================================ */

void* dsl_malloc(size_t size) {
    // Align to 8 bytes
    size = (size + 7) & ~7;
    
    if (heap_offset + size > HEAP_SIZE) {
        return NULL;  // Out of memory
    }
    
    void* ptr = &heap_memory[heap_offset];
    heap_offset += size;
    return ptr;
}

void dsl_free(void* ptr) {
    // Simple bump allocator doesn't support free
    // For embedded, consider using a proper allocator
    (void)ptr;
}

void* dsl_realloc(void* ptr, size_t size) {
    // Simplified realloc
    void* new_ptr = dsl_malloc(size);
    if (new_ptr && ptr) {
        // Copy old data (assumes we know the size)
        uint8_t* src = (uint8_t*)ptr;
        uint8_t* dst = (uint8_t*)new_ptr;
        for (size_t i = 0; i < size; i++) {
            dst[i] = src[i];
        }
    }
    return new_ptr;
}

/* ============================================================================
 * String Operations (no stdlib)
 * ============================================================================ */

size_t dsl_strlen(const char* str) {
    size_t len = 0;
    while (str[len]) len++;
    return len;
}

char* dsl_strcpy(char* dest, const char* src) {
    char* d = dest;
    while ((*d++ = *src++));
    return dest;
}

/* ============================================================================
 * Simple Integer to String Conversion
 * ============================================================================ */

char* dsl_i32_to_string(int32_t value) {
    static char buffer[32];
    char* ptr = buffer + 31;
    int is_negative = value < 0;
    
    *ptr = '\0';
    
    if (value == 0) {
        *--ptr = '0';
        return ptr;
    }
    
    if (is_negative) value = -value;
    
    while (value > 0) {
        *--ptr = '0' + (value % 10);
        value /= 10;
    }
    
    if (is_negative) *--ptr = '-';
    
    return ptr;
}

char* dsl_i64_to_string(int64_t value) {
    return dsl_i32_to_string((int32_t)value);
}

char* dsl_int64_to_string(int64_t value) {
    return dsl_i32_to_string((int32_t)value);
}

/* ============================================================================
 * UART Output (customize for your hardware)
 * ============================================================================ */

void uart_putc(char c) {
    // Wait for TX ready
    while (!(UART_SR & 0x80));
    UART_DR = c;
}

void dcl_print(const char* str) {
    if (!str) return;
    
    while (*str) {
        uart_putc(*str++);
    }
}

void dcl_println(const char* str) {
    dcl_print(str);
    uart_putc('\n');
}

/* ============================================================================
 * Embedded System Functions
 * ============================================================================ */

// Busy-wait delay (customize for your CPU frequency)
void dsl_embedded_delay(uint32_t cycles) {
    for (volatile uint32_t i = 0; i < cycles; i++) {
        __asm__ volatile("nop");
    }
}

// Halt processor
void dsl_embedded_halt() {
    while (1) {
        __asm__ volatile("wfi");  // Wait for interrupt
    }
}

/* ============================================================================
 * Panic Handler
 * ============================================================================ */

void dsl_panic(const char* message) {
    dcl_println("PANIC: ");
    dcl_println(message);
    dsl_embedded_halt();
}
