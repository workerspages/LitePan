package config

import (
	"os"
	"path/filepath"
	"strings"
)

type Config struct {
	DataDir    string
	StrmDir    string
	DBDriver   string // sqlite, mysql
	DBDsn      string
	ListenAddr string
	LogLevel   string
}

func Default() Config {
	dataDir := "./data"
	return Config{
		DataDir:    dataDir,
		StrmDir:    "./strm",
		DBDriver:   "sqlite",
		DBDsn:      filepath.Join(dataDir, "litepan.db"),
		ListenAddr: ":8080",
		LogLevel:   "info",
	}
}

// StrmDirForData 返回数据目录同级�?STRM 目录�?
func StrmDirForData(dataDir string) string {
	return filepath.Join(filepath.Dir(filepath.Clean(dataDir)), "strm")
}

// Load 在默认值基础上应�?LITEPAN_* 环境变量覆盖�?
func Load() Config {
	c := Default()
	if v := strings.TrimSpace(os.Getenv("LITEPAN_DATA_DIR")); v != "" {
		c.DataDir = v
		c.DBDsn = filepath.Join(v, "litepan.db")
		if strings.TrimSpace(os.Getenv("LITEPAN_STRM_DIR")) == "" {
			c.StrmDir = StrmDirForData(v)
		}
	}
	if v := strings.TrimSpace(os.Getenv("LITEPAN_STRM_DIR")); v != "" {
		c.StrmDir = v
	}
	if v := os.Getenv("LITEPAN_DB_DRIVER"); v != "" {
		c.DBDriver = v
	}
	if v := os.Getenv("LITEPAN_DB_DSN"); v != "" {
		c.DBDsn = v
	}
	// 兼容旧的环境变量
	if v := os.Getenv("LITEPAN_DB_PATH"); v != "" {
		if c.DBDriver == "sqlite" {
			c.DBDsn = v
		}
	}
	if v := os.Getenv("LITEPAN_LISTEN"); v != "" {
		c.ListenAddr = v
	}
	if v := os.Getenv("LITEPAN_LOG_LEVEL"); v != "" {
		c.LogLevel = strings.ToLower(v)
	}
	return c
}
