package main

import (
	"net/http"
	"os"
	"time"
)

func main() {
	url := "http://127.0.0.1:8081/health/ready"
	if len(os.Args) == 2 {
		url = os.Args[1]
	}

	client := http.Client{Timeout: 2 * time.Second}
	response, err := client.Get(url)
	if err != nil {
		os.Exit(1)
	}
	defer response.Body.Close()

	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		os.Exit(1)
	}
}
