# Lab 054 — GoLang Introduction for Terraform Developers
**By: Saravanan Sundaramoorthy**
**Environment:** Local (Linux/macOS)
**Time:** ~45 min

---

## Overview

Terraform itself is written in Go. Every provider you use — AWS, Azure, GCP — is a Go binary built with the `terraform-plugin-sdk`. Terratest, the most popular Terraform integration-testing framework, is also Go. If you want to write custom providers or automated infrastructure tests, Go is non-negotiable.

This lab introduces Go from scratch, targeting Terraform developers who already know HCL and want to level up to writing Terratest tests and eventually custom providers.

### What you will build

| Part | Topic |
|------|-------|
| 1 | Install Go and verify the toolchain |
| 2 | Hello World — modules, fmt, build |
| 3 | Go language basics — variables, functions, structs, error handling |
| 4 | HTTP requests (the pattern Terratest uses to probe endpoints) |
| 5 | Go modules — dependency management |
| 6 | Terratest preview — a minimal infrastructure test |

---

## Why Go, Not Python or Bash?

| Concern | Bash | Python | Go |
|---------|------|--------|----|
| Typed | No | Optional (mypy) | Yes — compile-time |
| Compiled binary | No | No (needs interpreter) | Yes — single static binary |
| Error handling | Manual `$?` | Exceptions | Explicit `if err != nil` |
| Concurrency | Hard | GIL limited | Goroutines (built-in) |
| Terraform provider SDK | No | No | Yes — only Go |
| Terratest | No | No | Yes — only Go |

Go gives you the confidence of a compiled language — if it compiles, the types are correct — combined with a fast feedback loop (compiles in seconds, not minutes).

---

## Prerequisites

- Ubuntu/Debian Linux (the snap path) OR any Linux/macOS (manual path)
- Internet access for downloading Go and modules
- A terminal

---

## Part 1 — Install Go

### Option A — Snap (easiest on Ubuntu)

```bash
sudo snap install go --classic
go version
```

Expected output:
```
go version go1.21.x linux/amd64
```

### Option B — Manual install (any Linux)

Use this on systems without snap, or when you need a specific Go version.

```bash
# Download the Go 1.21.1 tarball
wget https://go.dev/dl/go1.21.1.linux-amd64.tar.gz

# Remove any existing Go installation first to avoid mixing versions
sudo rm -rf /usr/local/go

# Extract into /usr/local
tar -zxf go1.21.1.linux-amd64.tar.gz
sudo mv go /usr/local/

# Add Go's bin directory to PATH — do this once
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

# Confirm the installation
go version
```

Expected output:
```
go version go1.21.1 linux/amd64
```

### Understand the Go toolchain commands

```bash
# Show all available go subcommands
go help

# Show environment variables Go uses (GOPATH, GOROOT, etc.)
go env

# Where does Go store downloaded module caches?
go env GOPATH
```

> **Note for Terraform devs:** Think of `go env` like `terraform env` — it shows you the working context. `GOPATH` is where Go stores your downloaded dependencies, similar to the `.terraform` directory in a Terraform project.

---

## Part 2 — Hello World

Every Go program lives inside a **module**. A module is a directory with a `go.mod` file — the equivalent of `package.json` in Node or `requirements.txt` in Python.

### Create the project

```bash
# Create a fresh directory for the project
mkdir ~/robochef-hello && cd ~/robochef-hello

# Initialise a new Go module
# The module path is like a package name — use your domain or a simple identifier
go mod init robochef.co/saravanans/hello
```

This creates `go.mod`:
```
module robochef.co/saravanans/hello

go 1.21.1
```

### Write main.go

Create the file `main.go` in `~/robochef-hello/`:

```go
package main

import "fmt"

func main() {
    fmt.Println("Hello Folks — from robochef.co/saravanans")
}
```

Key points:
- Every Go file starts with `package <name>`. The entry point package is always `package main`.
- `import "fmt"` pulls in the standard-library formatting package — no installation needed.
- `func main()` is the program entry point — exactly one per program.
- `fmt.Println` prints a line with a newline at the end.

### Format, run, and build

```bash
# Auto-format the code (enforces the official Go style — no arguments needed)
go fmt

# Run without compiling to a binary — great during development
go run main.go

# Compile to a binary named after the directory
go build

# Run the compiled binary
./robochef-hello
```

Expected output for both `go run` and `./robochef-hello`:
```
Hello Folks — from robochef.co/saravanans
```

> **Analogy:** `go run` is like `terraform plan` — quick, no artefact. `go build` is like `terraform apply` — produces a real output (a binary).

---

## Part 3 — Go Language Basics for Terraform Developers

### 3.1 Variables

Go has two ways to declare variables. Understanding both is essential before reading Terratest code.

```go
package main

import "fmt"

func main() {
    // Style 1 — explicit type declaration (var keyword)
    // Use this at the package level or when the type is not obvious from the value
    var siteName string = "robochef.co"
    var port int = 8080
    var isProduction bool = false

    // Style 2 — short variable declaration (:=)
    // ONLY valid inside a function body. Go infers the type automatically.
    region := "us-east-1"
    instanceCount := 3
    apiEndpoint := "https://api.robochef.co/saravanans/health"

    fmt.Println("Site:", siteName)
    fmt.Println("Port:", port)
    fmt.Println("Production:", isProduction)
    fmt.Println("Region:", region)
    fmt.Println("Instances:", instanceCount)
    fmt.Println("API:", apiEndpoint)

    // Constants — value cannot change after declaration
    const maxRetries = 5
    fmt.Println("Max retries:", maxRetries)
}
```

> **Key difference from Python/HCL:** Go is statically typed. Once a variable is declared as `string`, you cannot assign an `int` to it. The compiler enforces this — you find bugs before runtime.

### 3.2 Functions

```go
package main

import "fmt"

// Function with two string parameters, returns a string
// Syntax: func <name>(<param> <type>, ...) <return-type>
func buildEndpoint(base string, path string) string {
    return base + path
}

// Function that returns two values — this is very common in Go
// The second return value is conventionally an error
func divide(a float64, b float64) (float64, error) {
    if b == 0 {
        // errors.New creates a simple error value
        return 0, fmt.Errorf("robochef.co/saravanans: cannot divide by zero")
    }
    return a / b, nil // nil means "no error"
}

func main() {
    url := buildEndpoint("https://robochef.co", "/saravanans/menu")
    fmt.Println("Endpoint:", url)

    result, err := divide(10.0, 3.0)
    if err != nil {
        fmt.Println("Error:", err)
        return
    }
    fmt.Printf("Result: %.2f\n", result)
}
```

> **Pattern alert:** The `value, err := someFunc()` pattern and the `if err != nil` check immediately after it are the most important Go idiom. Every Terratest function works this way. You will write it dozens of times.

### 3.3 Slices and Maps

These are the Go equivalents of Python lists and dicts, and the HCL `list` and `map` types.

```go
package main

import "fmt"

func main() {
    // Slice — ordered, variable-length list
    chefs := []string{"saravanans", "alice", "bob"}
    chefs = append(chefs, "carol") // add an element
    fmt.Println("Chefs:", chefs)
    fmt.Println("First chef:", chefs[0])
    fmt.Println("Count:", len(chefs))

    // Iterate over a slice
    for index, name := range chefs {
        fmt.Printf("  [%d] %s\n", index, name)
    }

    // Map — key-value store (like HCL map or Python dict)
    config := map[string]string{
        "site":    "robochef.co",
        "owner":   "saravanans",
        "region":  "us-east-1",
        "env":     "production",
    }

    // Access a value
    fmt.Println("Owner:", config["owner"])

    // Safe lookup — check whether the key exists
    if value, ok := config["region"]; ok {
        fmt.Println("Region found:", value)
    }

    // Iterate over a map
    for key, val := range config {
        fmt.Printf("  %s = %s\n", key, val)
    }
}
```

### 3.4 Structs — Go's version of HCL objects

In HCL you write `object({ name = string, count = number })`. In Go you define a `struct`.

```go
package main

import "fmt"

// Define a struct type — fields have names and types
type RoboChefServer struct {
    Name       string
    Region     string
    InstanceType string
    Count      int
    Production bool
}

// Method on the struct — similar to a Python class method
// The receiver (s RoboChefServer) is like Python's self
func (s RoboChefServer) Summary() string {
    env := "staging"
    if s.Production {
        env = "production"
    }
    return fmt.Sprintf("%s (%s) — %d x %s in %s", s.Name, env, s.Count, s.InstanceType, s.Region)
}

func main() {
    // Create a struct value
    web := RoboChefServer{
        Name:         "robochef-web",
        Region:       "us-east-1",
        InstanceType: "t3.micro",
        Count:        3,
        Production:   true,
    }

    fmt.Println(web.Summary())
    fmt.Println("Region:", web.Region)

    // Slice of structs — very common in Terraform provider code
    servers := []RoboChefServer{
        {Name: "robochef-api", Region: "us-east-1", InstanceType: "t3.small", Count: 2, Production: true},
        {Name: "robochef-worker", Region: "eu-west-1", InstanceType: "t3.micro", Count: 1, Production: false},
    }

    for _, s := range servers {
        fmt.Println(" -", s.Summary())
    }
}
```

### 3.5 Interfaces

Interfaces define behaviour — any type that implements the methods satisfies the interface. This is how Terraform providers plug in: they satisfy the `terraform.ResourceProvider` interface.

```go
package main

import "fmt"

// Interface — defines a contract (a set of methods a type must have)
type HealthChecker interface {
    HealthEndpoint() string
    IsHealthy() bool
}

// Two concrete types that both satisfy HealthChecker

type WebServer struct {
    Host string
    Port int
}

func (w WebServer) HealthEndpoint() string {
    return fmt.Sprintf("http://%s:%d/health", w.Host, w.Port)
}

func (w WebServer) IsHealthy() bool {
    // In real code this would make an HTTP call — see Part 4
    return true
}

type GRPCServer struct {
    Host string
}

func (g GRPCServer) HealthEndpoint() string {
    return fmt.Sprintf("grpc://%s:50051/grpc.health.v1.Health/Check", g.Host)
}

func (g GRPCServer) IsHealthy() bool {
    return true
}

// Function that accepts any HealthChecker — polymorphism
func printStatus(svc HealthChecker) {
    status := "DOWN"
    if svc.IsHealthy() {
        status = "UP"
    }
    fmt.Printf("  %s — %s\n", svc.HealthEndpoint(), status)
}

func main() {
    services := []HealthChecker{
        WebServer{Host: "api.robochef.co", Port: 8080},
        WebServer{Host: "www.robochef.co", Port: 443},
        GRPCServer{Host: "grpc.robochef.co"},
    }

    fmt.Println("Service Health — robochef.co/saravanans:")
    for _, svc := range services {
        printStatus(svc)
    }
}
```

### 3.6 Error Handling

This is the most important section for Terratest. Go does not use exceptions. Every function that can fail returns an `error` as its last return value. You check it explicitly.

```go
package main

import (
    "errors"
    "fmt"
    "strconv"
)

// Custom error type for domain-specific errors
type RoboChefError struct {
    Code    int
    Message string
}

// Implement the built-in error interface (requires an Error() string method)
func (e *RoboChefError) Error() string {
    return fmt.Sprintf("robochef.co error %d: %s", e.Code, e.Message)
}

// Function that can fail — returns (value, error)
func parsePortNumber(input string) (int, error) {
    port, err := strconv.Atoi(input) // Atoi converts string -> int
    if err != nil {
        // Wrap the low-level error with context
        return 0, fmt.Errorf("robochef.co/saravanans: invalid port %q: %w", input, err)
    }
    if port < 1 || port > 65535 {
        return 0, &RoboChefError{
            Code:    400,
            Message: fmt.Sprintf("port %d is out of valid range 1-65535", port),
        }
    }
    return port, nil
}

func main() {
    // --- Happy path ---
    port, err := parsePortNumber("8080")
    if err != nil {
        fmt.Println("Error:", err)
    } else {
        fmt.Println("Parsed port:", port)
    }

    // --- Error path: not a number ---
    _, err = parsePortNumber("abc")
    if err != nil {
        fmt.Println("Error:", err)
    }

    // --- Error path: out of range ---
    _, err = parsePortNumber("99999")
    if err != nil {
        fmt.Println("Error:", err)

        // Type-assert to get the custom error fields
        var rcErr *RoboChefError
        if errors.As(err, &rcErr) {
            fmt.Printf("  -> Code: %d, Message: %s\n", rcErr.Code, rcErr.Message)
        }
    }
}
```

> **Rule:** Never ignore an error. If you see `_, err := someFunc()` where the blank identifier discards the value, the `if err != nil` block must still follow. Terratest will call `t.Fatal(err)` on failure — your test stops and the error is printed.

---

## Part 4 — HTTP Requests (The Terratest Pattern)

Terratest commonly deploys infrastructure, then hits an HTTP endpoint to verify the deployment. Here is the Go pattern for that.

```go
package main

import (
    "fmt"
    "io"
    "net/http"
    "strings"
    "time"
)

// checkEndpoint makes a GET request to a URL and returns the response body.
// This is the exact pattern used by Terratest's http_helper module.
func checkEndpoint(url string) (string, error) {
    // Create a client with a timeout — never use the default client in production
    client := &http.Client{
        Timeout: 10 * time.Second,
    }

    // Make the GET request
    resp, err := client.Get(url)
    if err != nil {
        return "", fmt.Errorf("robochef.co/saravanans: GET %s failed: %w", url, err)
    }
    defer resp.Body.Close() // Always close the body — resource leak if you don't

    // Read the entire response body into a byte slice
    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return "", fmt.Errorf("robochef.co/saravanans: reading response body: %w", err)
    }

    // Check the HTTP status code
    if resp.StatusCode != http.StatusOK {
        return "", fmt.Errorf("robochef.co/saravanans: expected 200, got %d from %s", resp.StatusCode, url)
    }

    return string(body), nil
}

func main() {
    // Using a public echo service for the demo — in Terratest this would be
    // the URL output by your Terraform deployment
    url := "https://httpbin.org/get"

    fmt.Printf("Checking endpoint: %s\n", url)
    body, err := checkEndpoint(url)
    if err != nil {
        fmt.Println("Health check failed:", err)
        return
    }

    // Print just the first 200 characters so the output is readable
    preview := body
    if len(preview) > 200 {
        preview = preview[:200] + "..."
    }
    fmt.Println("Response received:")
    fmt.Println(preview)

    // In a real Terratest test you would assert on the content
    if strings.Contains(body, "httpbin") {
        fmt.Println("\nAssertion PASSED — response body contains expected content")
    } else {
        fmt.Println("\nAssertion FAILED — response body did not match")
    }
}
```

Run it:

```bash
go run main.go
```

> **Terraform connection:** When Terraform deploys an EC2 instance with an ALB, the ALB DNS name is exposed as an output. Terratest reads that output (`terraform.Output(t, terraformOptions, "alb_dns_name")`), constructs the URL, and calls something very similar to `checkEndpoint` above. You have just written the core of a Terratest assertion.

---

## Part 5 — Go Modules (Dependency Management)

Go modules are Go's built-in dependency manager — equivalent to `npm` for Node.js or `pip` for Python, but with no separate tool installation required.

### Key files

| File | Purpose |
|------|---------|
| `go.mod` | Declares the module name and lists direct dependencies with versions |
| `go.sum` | Cryptographic checksums of every dependency — never hand-edit this |

### Workflow

```bash
# 1. Initialise a module (creates go.mod)
go mod init robochef.co/saravanans/infra-tools

# 2. Add an import in your .go file, then fetch it
go get github.com/stretchr/testify@v1.8.4

# 3. After adding/removing imports, sync go.mod and go.sum
go mod tidy

# 4. Download all dependencies locally (useful in CI before running tests)
go mod download

# 5. List all dependencies
go list -m all
```

### Example go.mod after adding testify and Terratest

```
module robochef.co/saravanans/infra-tests

go 1.21.1

require (
    github.com/gruntwork-io/terratest v0.46.7
    github.com/stretchr/testify v1.8.4
)
```

> `go.sum` is like a lock file — commit both `go.mod` and `go.sum` to version control. This ensures every developer and every CI run uses exactly the same dependency versions.

### Using an external package — a complete example

Create `~/robochef-json/main.go`:

```go
package main

import (
    "encoding/json"
    "fmt"
    "log"
)

// RoboChefConfig represents deployment configuration for robochef.co
type RoboChefConfig struct {
    Site        string            `json:"site"`
    Owner       string            `json:"owner"`
    Environment string            `json:"environment"`
    Tags        map[string]string `json:"tags"`
}

func main() {
    // Marshal a Go struct to JSON — the backtick annotations define JSON field names
    cfg := RoboChefConfig{
        Site:        "robochef.co",
        Owner:       "saravanans",
        Environment: "production",
        Tags: map[string]string{
            "project":    "robochef",
            "managed-by": "terraform",
            "team":       "saravanans",
        },
    }

    // Encode Go struct -> JSON bytes
    data, err := json.MarshalIndent(cfg, "", "  ")
    if err != nil {
        log.Fatalf("robochef.co/saravanans: marshal error: %v", err)
    }
    fmt.Println("Serialised config:")
    fmt.Println(string(data))

    // Decode JSON bytes -> Go struct
    jsonInput := `{"site":"robochef.co","owner":"saravanans","environment":"staging","tags":{"project":"robochef"}}`
    var parsed RoboChefConfig
    if err := json.Unmarshal([]byte(jsonInput), &parsed); err != nil {
        log.Fatalf("robochef.co/saravanans: unmarshal error: %v", err)
    }
    fmt.Printf("\nParsed site: %s, env: %s\n", parsed.Site, parsed.Environment)
}
```

```bash
cd ~/robochef-json
go mod init robochef.co/saravanans/json-demo
go run main.go
```

The `encoding/json` package is in the standard library — no `go get` needed.

---

## Part 6 — Terratest Preview

Terratest is a Go testing framework from Gruntwork that deploys real infrastructure with Terraform, runs assertions against it (often HTTP checks like Part 4), and tears it down.

### Project structure

```
robochef-infra/
├── main.tf          <- Terraform configuration
├── variables.tf
├── outputs.tf
└── test/
    └── robochef_test.go   <- Terratest file
```

### The Terraform module under test

`main.tf`:
```hcl
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

resource "local_file" "robochef_config" {
  content  = "site=robochef.co owner=saravanans env=${var.environment}"
  filename = "${path.module}/robochef_output.txt"
}

variable "environment" {
  type    = string
  default = "staging"
}

output "config_file_path" {
  value = local_file.robochef_config.filename
}

output "site_name" {
  value = "robochef.co"
}
```

### The Terratest file

`test/robochef_test.go`:

```go
package test

import (
    "os"
    "strings"
    "testing"

    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
)

// TestRoboChefConfig deploys the local_file Terraform module, validates
// the outputs, and destroys everything when the test ends.
func TestRoboChefConfig(t *testing.T) {
    t.Parallel() // run this test in parallel with other tests in the package

    // Define where the Terraform module lives and what variables to pass
    terraformOptions := &terraform.Options{
        // Path to the root module being tested
        TerraformDir: "../",

        // Input variables — equivalent to -var flags on the CLI
        Vars: map[string]interface{}{
            "environment": "test",
        },

        // Disable colours in output for cleaner CI logs
        NoColor: true,
    }

    // terraform destroy at the end, no matter what happens
    // defer runs when the surrounding function returns — even on test failure
    defer terraform.Destroy(t, terraformOptions)

    // terraform init && terraform apply -auto-approve
    // If this fails, the test fails immediately (require vs assert)
    terraform.InitAndApply(t, terraformOptions)

    // Read the outputs from the Terraform state
    configFilePath := terraform.Output(t, terraformOptions, "config_file_path")
    siteName := terraform.Output(t, terraformOptions, "site_name")

    // Assert on the outputs
    assert.Equal(t, "robochef.co", siteName,
        "Expected site_name output to be robochef.co")

    assert.True(t, strings.HasSuffix(configFilePath, "robochef_output.txt"),
        "Expected config_file_path to end with robochef_output.txt")

    // Assert on the file content that Terraform created
    content, err := os.ReadFile(configFilePath)
    require.NoError(t, err, "robochef.co/saravanans: could not read config file")

    assert.Contains(t, string(content), "env=test",
        "Expected file to contain env=test")

    assert.Contains(t, string(content), "robochef.co",
        "Expected file to contain robochef.co")

    t.Logf("robochef.co/saravanans: test passed — config file at %s", configFilePath)
}
```

### go.mod for the test

```bash
cd robochef-infra/test
go mod init robochef.co/saravanans/infra-tests
go get github.com/gruntwork-io/terratest@v0.46.7
go get github.com/stretchr/testify@v1.8.4
go mod tidy
```

### Run the test

```bash
# Run with verbose output and a 10-minute timeout (terraform can be slow)
go test -v -timeout 10m ./...
```

Expected output:
```
=== RUN   TestRoboChefConfig
=== PAUSE TestRoboChefConfig
=== CONT  TestRoboChefConfig
    robochef_test.go: Running command terraform with args [init -upgrade=false]
    robochef_test.go: Running command terraform with args [apply -input=false -auto-approve ...]
    robochef_test.go: Running command terraform with args [output -no-color -json config_file_path]
    robochef_test.go: Running command terraform with args [output -no-color -json site_name]
    robochef_test.go: robochef.co/saravanans: test passed — config file at .../robochef_output.txt
    robochef_test.go: Running command terraform with args [destroy -auto-approve ...]
--- PASS: TestRoboChefConfig (12.34s)
PASS
ok      robochef.co/saravanans/infra-tests      12.345s
```

> **What just happened:** You wrote a Go test that ran `terraform init`, `terraform apply`, read two outputs, asserted on their values, read a file on disk, asserted on its content, and finally ran `terraform destroy` — all automated. This is the full Terratest lifecycle. For a real AWS test you would swap the `local` provider for the `aws` provider and assert against real resource attributes.

---

## Key Concepts Cheatsheet

### Variable declaration quick reference

```go
// Package-level — must use var
var globalSite = "robochef.co"

func example() {
    // Inside function — use := for short declaration
    site := "robochef.co"
    count := 3

    // Explicit type (use when type is not obvious)
    var timeout int = 30

    // Multiple assignment
    host, port := "api.robochef.co", 8080

    _ = site; _ = count; _ = timeout; _ = host; _ = port // suppress unused warnings
}
```

### Error handling quick reference

```go
// Always check errors immediately after the call that can fail
result, err := someFunc()
if err != nil {
    return fmt.Errorf("robochef.co/saravanans: context about what failed: %w", err)
}
// Use result here — it is valid only if err == nil
```

### Go vs HCL mental model

| HCL concept | Go equivalent |
|-------------|---------------|
| `variable "x" {}` | `var x string` or `x :=` |
| `locals {}` | local variables inside a function |
| `output "x" {}` | function return value |
| `resource "aws_s3_bucket" "b" {}` | struct instantiation |
| `for_each` | `for _, item := range items {}` |
| `count` | `for i := 0; i < count; i++ {}` |
| `map(string)` | `map[string]string{}` |
| `list(string)` | `[]string{}` |
| `object({...})` | `struct { ... }` |

---

## Cleanup

```bash
# Remove compiled binaries
rm -f ~/robochef-hello/robochef-hello
rm -f ~/robochef-json/robochef-json

# Remove Go module caches if disk space is a concern
go clean -modcache

# Remove Terraform state and working directories from the preview module
rm -rf ~/robochef-infra/.terraform
rm -f ~/robochef-infra/terraform.tfstate
rm -f ~/robochef-infra/terraform.tfstate.backup
rm -f ~/robochef-infra/robochef_output.txt
```

---

## Summary

| Topic | Key takeaway |
|-------|-------------|
| Installation | `sudo snap install go --classic` or manual wget + tar |
| Hello World | `go mod init`, write `main.go`, `go run`, `go build` |
| Variables | `var` at package level; `:=` inside functions |
| Functions | Multiple return values; always `(value, error)` |
| Error handling | `if err != nil` immediately after every fallible call |
| Structs | Go's typed objects — maps to HCL `object({})` |
| Interfaces | Define behaviour; Terraform providers implement them |
| HTTP | `net/http` + `io.ReadAll` — the core Terratest probe pattern |
| Modules | `go mod init`, `go get`, `go mod tidy`, commit `go.sum` |
| Terratest | `terraform.InitAndApply` → assert outputs → `defer Destroy` |

---

## Next Steps

- **Lab 045** — Terraform Testing Manual to Terratest (the HCL side of the test)
- Write a Terratest for an AWS S3 bucket using `aws-sdk-go` to verify the bucket exists
- Explore `github.com/gruntwork-io/terratest/modules/aws` for AWS-specific helpers (`aws.GetS3ObjectContents`, `aws.GetPublicIpOfEc2Instance`, etc.)
- Read the Terraform Plugin SDK docs at [developer.hashicorp.com/terraform/plugin](https://developer.hashicorp.com/terraform/plugin) — everything there is Go
