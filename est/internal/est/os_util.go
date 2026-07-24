package est

import (
	"os"
	"path/filepath"
)

func osCreateTempCert(certPEM []byte) (string, error) {
	dir, err := os.MkdirTemp("", "est-leaf-*")
	if err != nil {
		return "", err
	}
	path := filepath.Join(dir, "leaf.pem")
	if err := os.WriteFile(path, certPEM, 0o600); err != nil {
		os.RemoveAll(dir)
		return "", err
	}
	return path, nil
}

func osRemoveTemp(certPath string) {
	os.RemoveAll(filepath.Dir(certPath))
}

func bytesTrimSpace(b []byte) []byte {
	for len(b) > 0 && (b[0] == ' ' || b[0] == '\n' || b[0] == '\r' || b[0] == '\t') {
		b = b[1:]
	}
	for len(b) > 0 {
		c := b[len(b)-1]
		if c != ' ' && c != '\n' && c != '\r' && c != '\t' {
			break
		}
		b = b[:len(b)-1]
	}
	return b
}
