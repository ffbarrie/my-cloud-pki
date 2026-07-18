package est

import (
	"bytes"
	"context"
	"encoding/base64"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func buildPKCS7(ctx context.Context, opensslPath string, certFiles ...string) ([]byte, error) {
	dir, err := os.MkdirTemp("", "est-p7-*")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(dir)

	outPath := filepath.Join(dir, "out.der")
	args := []string{"crl2pkcs7", "-nocrl", "-outform", "DER", "-out", outPath}
	for _, cert := range certFiles {
		args = append(args, "-certfile", cert)
	}

	cmd := exec.CommandContext(ctx, opensslPath, args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("pkcs7: %w: %s", err, strings.TrimSpace(stderr.String()))
	}
	return os.ReadFile(outPath)
}

func encodePKCS7Base64(der []byte) string {
	return base64.StdEncoding.EncodeToString(der)
}
