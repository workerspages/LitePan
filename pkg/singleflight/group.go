package singleflight

import (
	"context"
	"fmt"
	"sync"
)

// Group 合并同一 key 的并发调用：只执行一次 fn，其余等待并共享结果。
type Group[T any] struct {
	mu sync.Mutex
	m  map[string]*call[T]
}

type call[T any] struct {
	done chan struct{}
	val  T
	err  error
}

func (g *Group[T]) DoCtx(ctx context.Context, key string, fn func(context.Context) (T, error)) (T, error) {
	g.mu.Lock()
	if g.m == nil {
		g.m = make(map[string]*call[T])
	}
	if c, ok := g.m[key]; ok {
		g.mu.Unlock()
		return waitCall(ctx, c)
	}
	c := &call[T]{done: make(chan struct{})}
	g.m[key] = c
	g.mu.Unlock()

	func() {
		defer func() {
			// fn panic 也必须关闭 done 并删除 key，否则等待者永久阻塞、
			// 该 key 被永久毒化；panic 转为 error 返回给所有调用方。
			if r := recover(); r != nil {
				c.err = fmt.Errorf("singleflight %q: %v", key, r)
			}
			close(c.done)
			g.mu.Lock()
			delete(g.m, key)
			g.mu.Unlock()
		}()
		c.val, c.err = fn(ctx)
	}()
	return c.val, c.err
}

func waitCall[T any](ctx context.Context, c *call[T]) (T, error) {
	select {
	case <-ctx.Done():
		var zero T
		return zero, ctx.Err()
	case <-c.done:
		return c.val, c.err
	}
}
