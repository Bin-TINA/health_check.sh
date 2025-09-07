# VM Health Check

一个简单的 shell 脚本，用于检查 CPU 使用率、内存使用率、以及根分区磁盘占用，并给出健康度解释。

## 目录结构
```
.
├─ scripts/
│  └─ health_check.sh
└─ docs/
   └─ usage.md
```

## 快速开始
```bash
chmod +x scripts/health_check.sh
./scripts/health_check.sh
```

## 解释模式（作业要求）
```bash
./scripts/health_check.sh explain
```

示例输出：
```
===== VM 健康报告 =====
CPU: 23.4%
内存: 61.2%
磁盘: 54%
结论: healthy
原因: 无明显异常
======================
```

## JSON 输出
```bash
./scripts/health_check.sh --json
```

## 判定阈值
- CPU 使用率 > 85% 警告；> 95% 紧急  
- 内存使用率 > 85% 警告；> 95% 紧急  
- 磁盘已用 > 90% 警告；> 95% 紧急  
