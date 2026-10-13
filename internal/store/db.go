package store

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/glebarez/sqlite"
	"gorm.io/driver/mysql"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// DB 封装 GORM db
type DB struct {
	GormDB *gorm.DB
}

// Options 控制底层数据库的打开方式。
type Options struct {
	Driver string // "sqlite" 或 "mysql"
	DSN    string // 数据库连接串
	Memory bool   // true 时使用共享缓存内存库，供测试使用（仅对 sqlite 有效）
}

var memSeq atomic.Int64

// Open 按 Options 建立连接并完成连通性检查。
func Open(ctx context.Context, opts Options) (*DB, error) {
	if opts.Driver == "" {
		opts.Driver = "sqlite"
	}

	var dialector gorm.Dialector
	if opts.Driver == "mysql" {
		dsn := opts.DSN
		if !strings.Contains(dsn, "parseTime=") {
			if strings.Contains(dsn, "?") {
				dsn += "&parseTime=true&loc=Local"
			} else {
				dsn += "?parseTime=true&loc=Local"
			}
		}
		dialector = mysql.Open(dsn)
	} else {
		dsn := buildDSN(opts)
		dialector = sqlite.Open(dsn)
	}

	newLogger := logger.New(
		log.New(os.Stdout, "\r\n", log.LstdFlags),
		logger.Config{
			SlowThreshold:             time.Second,
			LogLevel:                  logger.Warn,
			IgnoreRecordNotFoundError: true,
			Colorful:                  false,
		},
	)

	gdb, err := gorm.Open(dialector, &gorm.Config{
		Logger: newLogger,
	})
	if err != nil {
		return nil, fmt.Errorf("open %s db: %w", opts.Driver, err)
	}

	sqlDB, err := gdb.DB()
	if err != nil {
		return nil, err
	}
	if opts.Driver == "sqlite" {
		sqlDB.SetMaxOpenConns(1)
	} else {
		sqlDB.SetMaxOpenConns(20)
		sqlDB.SetMaxIdleConns(5)
	}

	if err := sqlDB.PingContext(ctx); err != nil {
		return nil, fmt.Errorf("ping: %w", err)
	}
	return &DB{GormDB: gdb}, nil
}

func buildDSN(opts Options) string {
	if opts.Memory {
		name := "litepan_mem_" + strconv.FormatInt(memSeq.Add(1), 10)
		return "file:" + name + "?mode=memory&cache=shared" +
			"&_pragma=busy_timeout(5000)&_pragma=foreign_keys(on)"
	}
	return "file:" + opts.DSN +
		"?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)" +
		"&_pragma=foreign_keys(on)&_pragma=synchronous(NORMAL)"
}

func (db *DB) Close() error {
	sqlDB, err := db.GormDB.DB()
	if err != nil {
		return err
	}
	return sqlDB.Close()
}

var onConflictRegex = regexp.MustCompile(`(?i)ON CONFLICT\([^)]+\)\s+DO UPDATE SET`)
var excludedRegex = regexp.MustCompile(`(?i)excluded\.([a-zA-Z0-9_]+)`)

// mysqlReservedIdent 匹配用作列名的 MySQL 保留字（key、recursive 等在 SQLite 下合法）。
// 保持小写敏感：必须在 onConflictRegex 改写前执行，避免误伤改写后产生的
// "ON DUPLICATE KEY UPDATE" 中的关键字 KEY。
var mysqlReservedIdent = regexp.MustCompile(`\b(key|recursive)\b`)

func adjustQuery(dialectorName, query string) string {
	if dialectorName == "mysql" {
		query = mysqlReservedIdent.ReplaceAllString(query, "`$1`")
		query = onConflictRegex.ReplaceAllString(query, "ON DUPLICATE KEY UPDATE")
		query = excludedRegex.ReplaceAllString(query, "VALUES($1)")
	}
	return query
}

func (db *DB) ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error) {
	sqlDB, _ := db.GormDB.DB()
	return sqlDB.ExecContext(ctx, adjustQuery(db.GormDB.Dialector.Name(), query), args...)
}

func (db *DB) QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error) {
	sqlDB, _ := db.GormDB.DB()
	return sqlDB.QueryContext(ctx, adjustQuery(db.GormDB.Dialector.Name(), query), args...)
}

func (db *DB) QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row {
	sqlDB, _ := db.GormDB.DB()
	return sqlDB.QueryRowContext(ctx, adjustQuery(db.GormDB.Dialector.Name(), query), args...)
}

type TxWrapper struct {
	*sql.Tx
	dialectorName string
}

func (tx *TxWrapper) ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error) {
	return tx.Tx.ExecContext(ctx, adjustQuery(tx.dialectorName, query), args...)
}

func (tx *TxWrapper) QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error) {
	return tx.Tx.QueryContext(ctx, adjustQuery(tx.dialectorName, query), args...)
}

func (tx *TxWrapper) QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row {
	return tx.Tx.QueryRowContext(ctx, adjustQuery(tx.dialectorName, query), args...)
}

func (tx *TxWrapper) PrepareContext(ctx context.Context, query string) (*sql.Stmt, error) {
	return tx.Tx.PrepareContext(ctx, adjustQuery(tx.dialectorName, query))
}

func (db *DB) BeginTx(ctx context.Context, opts *sql.TxOptions) (*TxWrapper, error) {
	sqlDB, _ := db.GormDB.DB()
	tx, err := sqlDB.BeginTx(ctx, opts)
	if err != nil {
		return nil, err
	}
	return &TxWrapper{Tx: tx, dialectorName: db.GormDB.Dialector.Name()}, nil
}
