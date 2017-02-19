package main

import (
	"crypto/tls"
	"flag"
	"fmt"
	"math/rand"
	"net"
	"os"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/phuslu/glog"

	"./httpproxy"
	"./httpproxy/filters"
	"./httpproxy/helpers"
	"./httpproxy/storage"

	"./httpproxy/filters/gae"
	"./httpproxy/filters/php"
)

var (
	version  = "r9999"
	tls13rev = tls.TLS13Reversion
	http2rev = "?????"
)

func init() {
	rand.Seed(time.Now().UnixNano())
}

func main() {

	if len(os.Args) > 1 && os.Args[1] == "-version" {
		fmt.Print(version)
		return
	}

	helpers.SetFlagsIfAbsent(map[string]string{
		"logtostderr": "true",
		"v":           "2",
	})

	flag.Parse()

	gover := strings.Split(strings.TrimPrefix(runtime.Version(), "devel +"), " ")[0]

	switch runtime.GOARCH {
	case "386", "amd64":
		helpers.SetConsoleTitle(fmt.Sprintf("GoProxy %s (go/%s)", version, gover))
	}

	config := make(map[string]httpproxy.Config)
	filename := "httpproxy.json"
	err := storage.LookupStoreByFilterName("httpproxy").UnmarshallJson(filename, &config)
	if err != nil {
		fmt.Printf("storage.LookupStoreByFilterName(%#v) failed: %s\n", filename, err)
		return
	}

	fmt.Fprintf(os.Stderr, `------------------------------------------------------
GoProxy Version    : %s (go/%s tls13/%s http2/%s %s/%s)`,
		version, gover, tls13rev, http2rev, runtime.GOOS, runtime.GOARCH)
	for profile, config := range config {
		if !config.Enabled {
			continue
		}
		addr := config.Address
		if ip, port, err := net.SplitHostPort(addr); err == nil {
			switch ip {
			case "", "0.0.0.0", "::":
				if ip1, err := helpers.LocalPerferIPv4(); err == nil {
					ip = ip1.String()
				} else if ips, err := helpers.LocalIPv4s(); err == nil && len(ips) > 0 {
					ip = ips[0].String()
				}
			}
			addr = net.JoinHostPort(ip, port)
		}
		fmt.Fprintf(os.Stderr, `
GoProxy Profile    : %s
Listen Address     : %s
Enabled Filters    : %v`,
			profile,
			addr,
			fmt.Sprintf("%s|%s|%s", strings.Join(config.RequestFilters, ","), strings.Join(config.RoundTripFilters, ","), strings.Join(config.ResponseFilters, ",")))
		for _, fn := range config.RoundTripFilters {
			f, err := filters.GetFilter(fn)
			if err != nil {
				glog.Fatalf("filters.GetFilter(%#v) error: %+v", fn, err)
			}

			switch fn {
			case "autoproxy":
				fmt.Fprintf(os.Stderr, `
Pac Server         : http://%s/proxy.pac`, addr)
			case "gae":
				fmt.Fprintf(os.Stderr, `
GAE AppIDs         : %s`, strings.Join(f.(*gae.Filter).Config.AppIDs, "|"))
			case "php":
				urls := make([]string, 0)
				for _, s := range f.(*php.Filter).Config.Servers {
					urls = append(urls, s.URL)
				}
				fmt.Fprintf(os.Stderr, `
GAE AppIDs         : %s`, strings.Join(urls, "|"))
			}
		}
		go httpproxy.ServeProfile(config, "goproxy "+version)
	}
	fmt.Fprintf(os.Stderr, "\n------------------------------------------------------\n")

	if ws, ok := os.LookupEnv("GOPROXY_WAIT_SECONDS"); ok {
		if ws1, err := strconv.Atoi(ws); err == nil {
			time.Sleep(time.Duration(ws1) * time.Second)
			return
		}
	}

	select {}
}
