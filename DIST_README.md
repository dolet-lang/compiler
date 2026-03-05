# Dolet Compiler v0.3.0-beta — Windows x64

```
██████╗  ██████╗ ██╗     ███████╗████████╗
██╔══██╗██╔═══██╗██║     ██╔════╝╚══██╔══╝
██║  ██║██║   ██║██║     █████╗     ██║   
██║  ██║██║   ██║██║     ██╔══╝     ██║   
██████╔╝╚██████╔╝███████╗███████╗   ██║   
╚═════╝  ╚═════╝ ╚══════╝╚══════╝   ╚═╝  
```

A self-hosting systems programming language that compiles to native code via MLIR/LLVM.
No C runtime — pure Windows API.

---

## Quick Start

### 1. Extract the ZIP

Extract `dolet-v0.3.0-beta-windows-x64.zip` to any location, for example:

```
C:\dolet\
```

### 2. Write Your First Program

Create a file called `hello.dlt`:

```dolet
print("Hello from Dolet!")
```

### 3. Compile & Run

```batch
C:\dolet\bin\doletc.exe hello.dlt -o hello.exe
hello.exe
```

Output:
```
Hello from Dolet!
```

---

## Add to PATH (Use from Anywhere)

To use `doletc` from any directory in CMD/PowerShell, add the `bin\` folder to your system PATH.

### Option A: Temporary (Current Session Only)

```batch
set PATH=%PATH%;C:\dolet\bin
```

Now you can run from anywhere:
```batch
doletc hello.dlt -o hello.exe
```

### Option B: Permanent (Recommended)

#### Using Command Line (Run as Administrator):

```batch
setx PATH "%PATH%;C:\dolet\bin" /M
```

Restart your terminal after running the command.

#### Using Windows Settings:

1. Press **Win + S**, search for **"Environment Variables"**
2. Click **"Edit the system environment variables"**
3. Click **"Environment Variables..."** button
4. Under **"System variables"**, find **Path** and click **"Edit..."**
5. Click **"New"** and add the path to the `bin\` folder:
   ```
   C:\dolet\bin
   ```
6. Click **OK** on all dialogs
7. **Restart** your terminal

#### Verify:

```batch
doletc --help
```

If you see the usage message, you're all set!

---

## Usage

```
doletc <input.dlt> [-o output.exe] [--keep-mlir] [--keep-llvm] [--no-runtime]
```

| Option | Description |
|--------|-------------|
| `-o <path>` | Output executable path (default: `<input>.exe`) |
| `--keep-mlir` | Keep intermediate `.mlir` file |
| `--keep-llvm` | Keep intermediate `.ll` file |
| `--no-runtime` | Don't auto-import runtime libraries |

### Examples

```batch
doletc app.dlt                      :: Compiles to app.exe
doletc app.dlt -o myapp.exe         :: Custom output name
doletc app.dlt --keep-mlir          :: Keep .mlir for debugging
```

---

## Folder Structure

```
dolet-v0.3.0-beta-windows-x64/
├── bin/
│   └── doletc.exe              # The Dolet compiler
├── tools/
│   ├── clang.exe               # LLVM C compiler (for linking)
│   ├── lld-link.exe            # LLVM linker
│   └── mlir-translate.exe      # MLIR to LLVM IR translator
├── library/
│   ├── std/
│   │   ├── runtime/            # Low-level runtime (auto-imported)
│   │   ├── std/                # Standard library (print, File, etc.)
│   │   └── sys/windows/        # System libraries (.lib files)
│   └── importable/
│       ├── math/               # Math library
│       ├── net/                # Networking (TCP, HTTP, WebSocket)
│       └── random/             # Random number generation
└── README.md                   # This file
```

---

## Language Examples

### Variables & Functions

```dolet
x: i32 = 42
name: str = "Dolet"
print(x)
print(name)

fun add(a: i32, b: i32) -> i32:
    return a + b

result: i32 = add(10, 20)
print(result)
```

### Structs

```dolet
struct Point:
    x: f64
    y: f64

    fun distance(self, other: Point) -> f64:
        dx: f64 = self.x - other.x
        dy: f64 = self.y - other.y
        return Math.sqrt(dx * dx + dy * dy)

a: Point = Point(0.0, 0.0)
b: Point = Point(3.0, 4.0)
print(a.distance(b))
```

### Pattern Matching

```dolet
enum Color:
    Red
    Green
    Blue

c: Color = Color.Red
match c:
    case Color.Red:
        print("Red!")
    case Color.Green:
        print("Green!")
    case Color.Blue:
        print("Blue!")
```

### Generic Collections

```dolet
names: list<str> = ["Alice", "Bob", "Charlie"]
scores: map<str, i32> = {"Alice": 95, "Bob": 87}
```

---

## Requirements

- **Windows 10/11 x64**
- No additional dependencies needed — everything is included!

---

## Links

- **GitHub**: [github.com/dolet-lang](https://github.com/dolet-lang)
- **Compiler Source**: [github.com/dolet-lang/dolet-compiler](https://github.com/dolet-lang/dolet-compiler)
- **Standard Library**: [github.com/dolet-lang/library](https://github.com/dolet-lang/library)

---

Dolet Programming Language — v0.3.0-beta
