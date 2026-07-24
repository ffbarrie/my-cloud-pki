package ejbca

import (
	"bytes"
	"context"
	"encoding/pem"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const defaultEnrollTimeout = 45 * time.Second

type CMPClient struct {
	OpenSSLPath string
	URL         string
	Secret      string
	Ref         string
	SrvCert     string
}

func (c *CMPClient) EnrollCSR(ctx context.Context, csrDER []byte) ([]byte, error) {
	if _, ok := ctx.Deadline(); !ok {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, defaultEnrollTimeout)
		defer cancel()
	}

	dir, err := os.MkdirTemp("", "est-cmp-*")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(dir)

	csrPath := filepath.Join(dir, "request.csr")
	certPath := filepath.Join(dir, "issued.pem")
	secretPath := filepath.Join(dir, "cmp.secret")

	if err := os.WriteFile(csrPath, pemCSR(csrDER), 0o600); err != nil {
		return nil, err
	}
	if err := os.WriteFile(secretPath, []byte(c.Secret), 0o600); err != nil {
		return nil, err
	}

	server, path, err := splitServerPath(c.URL)
	if err != nil {
		return nil, err
	}

	args := []string{
		"cmp",
		"-cmd", "p10cr",
		"-server", server,
		"-path", path,
		"-srvcert", c.SrvCert,
		// file: avoids putting the HMAC secret on the process argv.
		"-secret", "file:" + secretPath,
		"-ref", c.Ref,
		"-csr", csrPath,
		"-certout", certPath,
	}

	cmd := exec.CommandContext(ctx, c.OpenSSLPath, args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		detail := strings.TrimSpace(stderr.String())
		if detail == "" {
			return nil, fmt.Errorf("cmp p10cr failed: %w", err)
		}
		return nil, fmt.Errorf("cmp p10cr failed: %w (%s)", err, detail)
	}

	return os.ReadFile(certPath)
}

func splitServerPath(raw string) (server, path string, err error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", "", fmt.Errorf("empty CMP URL")
	}
	if strings.HasPrefix(raw, "http://") {
		raw = strings.TrimPrefix(raw, "http://")
	} else if strings.HasPrefix(raw, "https://") {
		raw = strings.TrimPrefix(raw, "https://")
	} else {
		return "", "", fmt.Errorf("CMP URL must start with http:// or https://")
	}
	parts := strings.SplitN(raw, "/", 2)
	server = parts[0]
	if len(parts) == 2 {
		path = parts[1]
	}
	if path == "" {
		path = "/"
	}
	return server, path, nil
}

func pemCSR(der []byte) []byte {
	block := &pem.Block{Type: "CERTIFICATE REQUEST", Bytes: der}
	return pem.EncodeToMemory(block)
}
