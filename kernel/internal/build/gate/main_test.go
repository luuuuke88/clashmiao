package gate

import (
	"fmt"
	"os"
	"testing"
)

func TestMain(m *testing.M) {
	cleanup, err := Setup()
	if err != nil {
		fmt.Fprintln(os.Stderr, "gate setup:", err)
		os.Exit(1)
	}
	code := m.Run()
	cleanup()
	os.Exit(code)
}
