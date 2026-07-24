package est

import (
	"crypto/subtle"
	"encoding/base64"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"net/http"

	"github.com/ffbarrie/my-cloud-pki/est/internal/config"
	"github.com/ffbarrie/my-cloud-pki/est/internal/ejbca"
)

const simplereenrollDeferred = "simplereenroll is deferred to v1.1; see est/getting-started.md"

type Server struct {
	cfg config.Config
	cmp *ejbca.CMPClient
}

func NewServer(cfg config.Config) *Server {
	return &Server{
		cfg: cfg,
		cmp: &ejbca.CMPClient{
			OpenSSLPath: cfg.OpenSSLPath,
			URL:         cfg.EJBCACMPURL,
			Secret:      cfg.EJBCACMPSecret,
			Ref:         cfg.EJBCACMPRef,
			SrvCert:     cfg.EJBCACMPSrvCert,
		},
	}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.handleHealthz)
	mux.HandleFunc("/.well-known/est/cacerts", s.handleCACerts)
	mux.HandleFunc("/.well-known/est/simpleenroll", s.handleSimpleEnroll)
	mux.HandleFunc("/.well-known/est/simplereenroll", s.handleSimpleReenroll)
	return mux
}

func (s *Server) handleHealthz(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok\n"))
}

func (s *Server) handleCACerts(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	p7, err := buildPKCS7(r.Context(), s.cfg.OpenSSLPath, s.cfg.CACertsIssuing, s.cfg.CACertsRoot)
	if err != nil {
		log.Printf("cacerts: %v", err)
		http.Error(w, "failed to build cacerts", http.StatusInternalServerError)
		return
	}

	// RFC 7030: application/pkcs7-mime with base64 Content-Transfer-Encoding.
	w.Header().Set("Content-Type", "application/pkcs7-mime")
	w.Header().Set("Content-Transfer-Encoding", "base64")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(encodePKCS7Base64(p7)))
}

func (s *Server) handleSimpleEnroll(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !s.checkBasicAuth(r) {
		w.Header().Set("WWW-Authenticate", `Basic realm="EST"`)
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	csrDER, err := readCSRBody(r)
	if err != nil {
		http.Error(w, "invalid certificate request", http.StatusBadRequest)
		return
	}

	certPEM, err := s.cmp.EnrollCSR(r.Context(), csrDER)
	if err != nil {
		log.Printf("simpleenroll: %v", err)
		http.Error(w, "enrollment failed", http.StatusBadGateway)
		return
	}

	leafPath, cleanup, err := writeTempCert(certPEM)
	if err != nil {
		log.Printf("simpleenroll: %v", err)
		http.Error(w, "enrollment failed", http.StatusInternalServerError)
		return
	}
	defer cleanup()

	p7, err := buildPKCS7(r.Context(), s.cfg.OpenSSLPath, leafPath)
	if err != nil {
		log.Printf("simpleenroll: %v", err)
		http.Error(w, "enrollment failed", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/pkcs7-mime")
	w.Header().Set("Content-Transfer-Encoding", "base64")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(encodePKCS7Base64(p7)))
}

func (s *Server) handleSimpleReenroll(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	w.WriteHeader(http.StatusNotImplemented)
	_, _ = io.WriteString(w, simplereenrollDeferred+"\n")
}

func (s *Server) checkBasicAuth(r *http.Request) bool {
	user, pass, ok := r.BasicAuth()
	if !ok {
		return false
	}
	// Always compare both to avoid short-circuit timing on password.
	userOK := constantTimeEqual(user, s.cfg.RAUser)
	passOK := constantTimeEqual(pass, s.cfg.RAPass)
	return userOK&passOK == 1
}

func constantTimeEqual(a, b string) int {
	if len(a) != len(b) {
		// Length mismatch still runs a dummy compare of equal-length buffers.
		_ = subtle.ConstantTimeCompare([]byte(b), []byte(b))
		return 0
	}
	return subtle.ConstantTimeCompare([]byte(a), []byte(b))
}

func readCSRBody(r *http.Request) ([]byte, error) {
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	body = bytesTrimSpace(body)
	if len(body) == 0 {
		return nil, fmt.Errorf("empty request body")
	}

	if block, _ := pem.Decode(body); block != nil {
		if block.Type != "CERTIFICATE REQUEST" && block.Type != "NEW CERTIFICATE REQUEST" {
			return nil, fmt.Errorf("unexpected PEM type %q", block.Type)
		}
		return block.Bytes, nil
	}

	decoded, err := base64.StdEncoding.DecodeString(string(body))
	if err != nil {
		return nil, fmt.Errorf("body must be base64 PKCS#10 or PEM CSR")
	}
	return decoded, nil
}

func writeTempCert(certPEM []byte) (path string, cleanup func(), err error) {
	f, err := osCreateTempCert(certPEM)
	if err != nil {
		return "", nil, err
	}
	return f, func() { osRemoveTemp(f) }, nil
}
