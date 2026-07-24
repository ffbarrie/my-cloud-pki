package config

import (
	"fmt"
	"os"
)

type Config struct {
	ListenAddr string

	TLSCert string
	TLSKey  string

	RAUser string
	RAPass string

	EJBCACMPURL     string
	EJBCACMPSecret  string
	EJBCACMPRef     string
	EJBCACMPSrvCert string

	CACertsIssuing string
	CACertsRoot    string

	OpenSSLPath string
}

func Load() (Config, error) {
	cfg := Config{
		ListenAddr: env("EST_LISTEN_ADDR", ":8443"),

		TLSCert: env("EST_TLS_CERT", "/etc/est/artifacts/est-server.crt"),
		TLSKey:  env("EST_TLS_KEY", "/etc/est/artifacts/est-server.key"),

		RAUser: env("EST_RA_USER", ""),
		RAPass: env("EST_RA_PASS", ""),

		EJBCACMPURL:     env("EJBCA_CMP_URL", "http://ejbca:8080/ejbca/publicweb/cmp/mycloud"),
		EJBCACMPSecret:  env("EJBCA_CMP_SECRET", ""),
		EJBCACMPRef:     env("EJBCA_CMP_REF", "mycloud"),
		EJBCACMPSrvCert: env("EJBCA_CMP_SRVCERT", "/etc/est/artifacts/IssuingCA.cacert.pem"),

		CACertsIssuing: env("EST_CACERTS_ISSUING", "/etc/est/artifacts/IssuingCA.cacert.pem"),
		CACertsRoot:    env("EST_CACERTS_ROOT", "/etc/est/artifacts/bootstrap-root-ca.crt"),

		OpenSSLPath: env("OPENSSL_PATH", "openssl"),
	}

	if cfg.RAUser == "" || cfg.RAPass == "" {
		return cfg, fmt.Errorf("EST_RA_USER and EST_RA_PASS are required")
	}
	if cfg.EJBCACMPSecret == "" {
		return cfg, fmt.Errorf("EJBCA_CMP_SECRET is required")
	}
	return cfg, nil
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
