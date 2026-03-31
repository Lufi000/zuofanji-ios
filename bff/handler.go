package main

import (
	"bytes"
	"io"
	"log"
	"net/http"
	"time"
)

// DashScope OpenAI-compatible endpoint (通义千问视觉等)
const dashScopeChatURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"

// 识图请求体含 base64 图片，需大于 cycle_advisor 纯文本上限
const maxBodySize = 8 * 1024 * 1024 // 8 MiB

const requestTimeout = 120 * time.Second

type Proxy struct {
	APIKey   string
	AppToken string
}

func (p *Proxy) HandleCompletions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	token := r.Header.Get("X-App-Token")
	if token == "" || token != p.AppToken {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, maxBodySize+1))
	if err != nil {
		http.Error(w, `{"error":"failed to read request body"}`, http.StatusBadRequest)
		return
	}
	if len(body) > maxBodySize {
		http.Error(w, `{"error":"request body too large"}`, http.StatusRequestEntityTooLarge)
		return
	}

	ctx := r.Context()
	upReq, err := http.NewRequestWithContext(ctx, http.MethodPost, dashScopeChatURL, bytes.NewReader(body))
	if err != nil {
		http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
		return
	}
	upReq.Header.Set("Content-Type", "application/json")
	upReq.Header.Set("Authorization", "Bearer "+p.APIKey)

	client := &http.Client{Timeout: requestTimeout}
	upResp, err := client.Do(upReq)
	if err != nil {
		log.Printf("upstream error: %v", err)
		http.Error(w, `{"error":"upstream request failed"}`, http.StatusBadGateway)
		return
	}
	defer upResp.Body.Close()

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(upResp.StatusCode)
	if _, err := io.Copy(w, upResp.Body); err != nil {
		log.Printf("response copy error: %v", err)
	}
}
