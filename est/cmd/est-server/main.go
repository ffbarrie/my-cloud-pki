package main

import (
	"log"
	"net/http"
	"time"

	"github.com/ffbarrie/my-cloud-pki/est/internal/config"
	"github.com/ffbarrie/my-cloud-pki/est/internal/est"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	srv := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           est.NewServer(cfg).Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	log.Printf("est-server listening on %s", cfg.ListenAddr)
	log.Fatal(srv.ListenAndServeTLS(cfg.TLSCert, cfg.TLSKey))
}
