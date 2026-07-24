// 把 bundle 的 .srs rule-set 反编译成明文清单。
//
// 关键点：srs.Read(reader, recovery=true) 时，binary.go 会对域名规则调用
// matcher.Dump() 把 succinct trie 还原成 Domain/DomainSuffix 两个字符串
// 列表——域名数据是能导出的。
package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/sagernet/sing-box/common/srs"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: srsdump <file.srs>")
		os.Exit(2)
	}
	f, err := os.Open(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer f.Close()

	compat, err := srs.Read(f, true) // recovery=true 才会 Dump
	if err != nil {
		panic(err)
	}
	plain := compat.Options

	out := map[string][]string{
		"domain":        {},
		"domain_suffix": {},
		"ip_cidr":       {},
	}
	for _, rule := range plain.Rules {
		d := rule.DefaultOptions
		out["domain"] = append(out["domain"], d.Domain...)
		out["domain_suffix"] = append(out["domain_suffix"], d.DomainSuffix...)
		out["ip_cidr"] = append(out["ip_cidr"], d.IPCIDR...)
	}
	enc := json.NewEncoder(os.Stdout)
	if err := enc.Encode(out); err != nil {
		panic(err)
	}
}
