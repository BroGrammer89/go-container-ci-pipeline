package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func handler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "We're up and running!! Rocking Version: %v", os.Getenv("VERSION"))
}

func main() {
	http.HandleFunc("/", handler)

	certFile := os.Getenv("TLS_CERT_PATH")
	keyFile := os.Getenv("TLS_KEY_PATH")

	if certFile != "" && keyFile != "" {
		log.Printf("Starting HTTPS server on :8443")
		if err := http.ListenAndServeTLS(":8443", certFile, keyFile, nil); err != nil {
			log.Fatalf("HTTPS server failed: %v", err)
		}
		return
	}

	log.Printf("Starting HTTP server on :3000")
	if err := http.ListenAndServe(":3000", nil); err != nil {
		log.Fatalf("HTTP server failed: %v", err)
	}
}
