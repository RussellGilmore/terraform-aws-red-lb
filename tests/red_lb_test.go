package test

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

// marker is the page body the example targets serve.
const marker = "red-lb-ok"

func getAWSRegion() string {
	if r := os.Getenv("AWS_REGION"); r != "" {
		return r
	}
	if r := os.Getenv("AWS_DEFAULT_REGION"); r != "" {
		return r
	}
	return "us-east-1"
}

// pollHTTP requests url until check passes or 10 minutes elapse. Instance
// boot, target registration and health checks take a few minutes.
func pollHTTP(t *testing.T, ctx context.Context, client *http.Client, url string, check func(*http.Response, string) bool) {
	t.Helper()

	deadline := time.Now().Add(10 * time.Minute)
	last := "no response"

	for time.Now().Before(deadline) {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		if err != nil {
			t.Fatalf("Building request for %s: %v", url, err)
		}

		resp, err := client.Do(req)
		if err == nil {
			body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
			resp.Body.Close()
			if check(resp, string(body)) {
				return
			}
			last = fmt.Sprintf("status %d, Location %q, body %q",
				resp.StatusCode, resp.Header.Get("Location"), strings.TrimSpace(string(body)))
		} else {
			last = err.Error()
		}

		time.Sleep(10 * time.Second)
	}

	t.Fatalf("%s never passed its check; last result: %s", url, last)
}

// noRedirectClient returns redirects as responses instead of following them.
func noRedirectClient() *http.Client {
	return &http.Client{
		Timeout: 10 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
}

func servesMarker(resp *http.Response, body string) bool {
	return resp.StatusCode == http.StatusOK && strings.Contains(body, marker)
}

// NLB: TCP listener -> TCP target group, target admitting traffic only from
// the load balancer's security group.
func TestRedLbNetwork(t *testing.T) {
	t.Parallel()

	ctx := t.Context()
	id := strings.ToLower(random.UniqueId())

	opts := &terraform.Options{
		TerraformDir: "../examples/nlb",
		Vars: map[string]interface{}{
			"region":        getAWSRegion(),
			"project_name":  fmt.Sprintf("red-lb-nlb-%s", id),
			"lb_name":       fmt.Sprintf("rlb-n-%s", id),
			"instance_name": fmt.Sprintf("rlb-n-%s", id),
		},
	}

	defer test_structure.RunTestStage(t, "teardown", func() {
		terraform.DestroyContext(t, ctx, opts)
	})

	test_structure.RunTestStage(t, "setup", func() {
		terraform.InitAndApplyContext(t, ctx, opts)
	})

	test_structure.RunTestStage(t, "validate", func() {
		dns := terraform.OutputContext(t, ctx, opts, "lb_dns_name")
		if dns == "" {
			t.Fatal("Expected a load balancer DNS name.")
		}

		pollHTTP(t, ctx, noRedirectClient(), "http://"+dns+"/", servesMarker)
	})
}

// ALB: HTTP listener forwarding to an HTTP target group, plus a listener that
// redirects to HTTPS.
func TestRedLbApplication(t *testing.T) {
	t.Parallel()

	ctx := t.Context()
	id := strings.ToLower(random.UniqueId())

	opts := &terraform.Options{
		TerraformDir: "../examples/alb",
		Vars: map[string]interface{}{
			"region":        getAWSRegion(),
			"project_name":  fmt.Sprintf("red-lb-alb-%s", id),
			"lb_name":       fmt.Sprintf("rlb-a-%s", id),
			"instance_name": fmt.Sprintf("rlb-a-%s", id),
		},
	}

	defer test_structure.RunTestStage(t, "teardown", func() {
		terraform.DestroyContext(t, ctx, opts)
	})

	test_structure.RunTestStage(t, "setup", func() {
		terraform.InitAndApplyContext(t, ctx, opts)
	})

	test_structure.RunTestStage(t, "validate", func() {
		dns := terraform.OutputContext(t, ctx, opts, "lb_dns_name")
		if dns == "" {
			t.Fatal("Expected a load balancer DNS name.")
		}

		client := noRedirectClient()

		// Forward action: the target's page comes back through the ALB.
		pollHTTP(t, ctx, client, "http://"+dns+"/", servesMarker)

		// Redirect action: a 301 pointing at HTTPS.
		pollHTTP(t, ctx, client, "http://"+dns+":8081/", func(resp *http.Response, _ string) bool {
			return resp.StatusCode == http.StatusMovedPermanently &&
				strings.HasPrefix(resp.Header.Get("Location"), "https://")
		})
	})
}
