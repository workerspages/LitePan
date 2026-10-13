package app

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"litepan/internal/config"
	"litepan/internal/logx"
	"litepan/internal/settings"
	"litepan/internal/store"
)

type storeBundle struct {
	db       *store.DB
	store    *store.Store
	settings *settings.Service
}

func prepareDataDirs(cfg config.Config) error {
	if err := os.MkdirAll(cfg.DataDir, 0o755); err != nil {
		return fmt.Errorf("create data dir: %w", err)
	}
	if dir := filepath.Dir(cfg.DBPath); dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return fmt.Errorf("create db dir: %w", err)
		}
	}
	strmDir := strings.TrimSpace(cfg.StrmDir)
	if strmDir == "" {
		strmDir = config.StrmDirForData(cfg.DataDir)
	}
	if err := os.MkdirAll(strmDir, 0o755); err != nil {
		return fmt.Errorf("create strm dir: %w", err)
	}
	return nil
}

func openStore(ctx context.Context, cfg config.Config, logs *logx.Manager) (*storeBundle, error) {
	switch cfg.Database.Driver {
	case "sqlite", "mysql":
	default:
		return nil, fmt.Errorf("不支持的数据库驱动 %q（仅支持 sqlite/mysql，对应 LITEPAN_DB_DRIVER）", cfg.Database.Driver)
	}
	if cfg.Database.Driver == "mysql" && strings.TrimSpace(cfg.Database.DSN) == "" {
		return nil, fmt.Errorf("LITEPAN_DB_DRIVER=mysql 但 LITEPAN_DB_DSN 为空，拒绝静默降级启动")
	}
	db, err := store.Open(ctx, store.Options{
		Driver: cfg.Database.Driver,
		DSN:    cfg.Database.DSN})
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}
	if err := db.Migrate(ctx); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}
	if err := db.EnsureUploadTaskCrossColumns(ctx); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("repair upload_tasks schema: %w", err)
	}

	st := store.New(db)
	settingsSvc, err := settings.New(ctx, st.Configs)
	if err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("load settings: %w", err)
	}
	settingsSvc.SetLogger(logs.For(logx.ModuleConfig))
	logs.SetLevel(settingsSvc.String(settings.KeyLogLevel))

	return &storeBundle{db: db, store: st, settings: settingsSvc}, nil
}
