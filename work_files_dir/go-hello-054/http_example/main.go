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
