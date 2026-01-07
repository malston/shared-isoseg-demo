// ABOUTME: Simple Go app that displays Cloud Foundry instance environment variables
// ABOUTME: Used in dual-segment demo to show workload placement on isolation segments

package main

import (
	"fmt"
	"net/http"
	"os"
	"sort"
	"strings"
)

func main() {
	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/env", handleEnv)
	http.HandleFunc("/health", handleHealth)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	fmt.Printf("cf-env starting on port %s\n", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		fmt.Fprintf(os.Stderr, "Error starting server: %v\n", err)
		os.Exit(1)
	}
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")

	fmt.Fprintln(w, "=== CF Instance Info ===")
	fmt.Fprintf(w, "CF_INSTANCE_IP:    %s\n", os.Getenv("CF_INSTANCE_IP"))
	fmt.Fprintf(w, "CF_INSTANCE_INDEX: %s\n", os.Getenv("CF_INSTANCE_INDEX"))
	fmt.Fprintf(w, "CF_INSTANCE_GUID:  %s\n", os.Getenv("CF_INSTANCE_GUID"))
	fmt.Fprintf(w, "CF_INSTANCE_ADDR:  %s\n", os.Getenv("CF_INSTANCE_ADDR"))
	fmt.Fprintf(w, "INSTANCE_GUID:     %s\n", os.Getenv("INSTANCE_GUID"))
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "=== Application Info ===")
	fmt.Fprintf(w, "VCAP_APPLICATION present: %v\n", os.Getenv("VCAP_APPLICATION") != "")
	fmt.Fprintf(w, "MEMORY_LIMIT:      %s\n", os.Getenv("MEMORY_LIMIT"))
	fmt.Fprintf(w, "PORT:              %s\n", os.Getenv("PORT"))
}

func handleEnv(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")

	// Get all environment variables and sort them
	envVars := os.Environ()
	sort.Strings(envVars)

	fmt.Fprintln(w, "=== All Environment Variables ===")
	for _, env := range envVars {
		// Skip sensitive variables
		if strings.HasPrefix(env, "VCAP_SERVICES") {
			fmt.Fprintln(w, "VCAP_SERVICES=[REDACTED]")
			continue
		}
		fmt.Fprintln(w, env)
	}
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, `{"status":"healthy"}`)
}
