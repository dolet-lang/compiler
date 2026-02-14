# Importable Standard Libraries

**Tier 2**: System libraries - Require explicit `import` statement

## Libraries in This Category

### fs/ - Filesystem Library
- **File**: `libfs.dlib`
- **Import**: `import fs`
- **Provides**:
  - `fs.File` - File operations
  - `fs.Dir` - Directory operations
  - `fs.Path` - Path manipulation
  - `fs.open()` - Open files
  - `fs.read_dir()` - Read directory contents

### net/ - Networking Library
- **File**: `libnet.dlib`
- **Import**: `import net`
- **Provides**:
  - `net.TcpSocket` - TCP socket
  - `net.TcpServer` - TCP server
  - `net.UdpSocket` - UDP socket
  - `net.HttpResponse` - HTTP response
  - `net.tcp_connect()`, `net.tcp_bind()`, `net.http_get()`

### os/ - Operating System Library
- **File**: `libos.dlib`
- **Import**: `import os`
- **Provides**:
  - `os.get_env()` - Get environment variable
  - `os.get_pid()` - Get process ID
  - `os.exit()` - Exit program

### ffi/ - Foreign Function Interface Library
- **File**: `libffi.dlib`
- **Import**: `import ffi`
- **Provides**:
  - C standard library bindings
  - Platform-specific code interfaces

## Usage Examples

### File I/O Example
```dolet
import fs

fun main():
    // Write file
    use fs.open("data.txt", "w") as file:
        file.write("Hello from Dolet!")

    // Read file
    use fs.open("data.txt", "r") as file:
        content: ptr = file.read()
        print(content)
```

### Networking Example
```dolet
import net

fun main():
    socket: net.TcpSocket = net.tcp_connect("localhost", 8080)
    response: net.HttpResponse = net.http_get("https://api.example.com")
```

### OS Example
```dolet
import os

fun main():
    env_var: Option<str> = os.get_env("PATH")
    pid: i32 = os.get_pid()
    print(@"Process ID: {pid}")
```

### FFI Example
```dolet
import ffi

fun main():
    // C standard library bindings available
```

## Compiler Behavior

The Dolet compiler:
1. Parses `import` statements at compile time
2. Resolves library paths from `lib/importable-stdLibs/{library_name}/`
3. Loads the corresponding `.dlib` file
4. Makes the library's symbols available under the namespace

For example, `import fs` loads `lib/importable-stdLibs/fs/libfs.dlib`

---

**Path**: `dolet/lib/importable-stdLibs/`
**Category**: Importable Standard Libraries (Tier 2)
