package store

import (
	"context"

	"litepan/internal/domain"
)

// ConfigModel 用于 AutoMigrate
type ConfigModel struct {
	Key       string `gorm:"primaryKey;column:key"`
	Value     string `gorm:"column:value"`
	UpdatedAt string `gorm:"column:updated_at"`
}

func (ConfigModel) TableName() string { return "configs" }

// Migrate 自动应用数据库迁移
func (db *DB) Migrate(ctx context.Context) error {
	models := []interface{}{
		&domain.Account{},
		&domain.AuthState{},
		&ConfigModel{},
		&domain.Notification{},
		&domain.StrmTask{},
		&domain.StrmBranch{},
		&domain.ApiKey{},
		&domain.UploadTaskRecord{},
		&domain.MediaOrganizeTask{},
		&domain.FuseMount{},
		&domain.CacheRetentionTask{},
		&domain.AutomationRule{},
		&domain.AutomationRun{},
		&domain.OfflineDownloadTaskRecord{},
		&domain.StrmDirCacheEntry{},
		&domain.QuarkTVBinding{},
	}
	return db.GormDB.WithContext(ctx).AutoMigrate(models...)
}

func (db *DB) EnsureUploadTaskCrossColumns(ctx context.Context) error {
	// GORM AutoMigrate 会自动处理新增列
	return nil
}
