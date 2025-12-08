# 快速开始指南

## 5分钟上手 alphaFFM-go

### 1. 编译项目
```bash
cd /data/xiongle/alphaFFM-go
make
```

### 2. 选择你的样本格式

#### 方式A: FFM格式（显式域名）- 不需要配置

样本格式:
```
1 user:sex:1 user:age:0.3 item:f1:1
0 user:u123:1 item:i456:1 price:p1:0.5
```

训练:
```bash
cat train.txt | ./bin/ffm_train -m model.txt -dim 1,1,8 -core 4
```

预测:
```bash
cat test.txt | ./bin/ffm_predict -m model.txt -dim 8 -out pred.txt -core 4
```

#### 方式B: FM格式（需要配置文件）- 推荐

样本格式:
```
1 sex:1 age:0.3 f1:1 f2:0.4
0 51539607553:1 55834574849:1 sex:0
```

配置文件 `config.txt`:
```
sex user
age user
f1 item
f2 item
```

训练:
```bash
cat train.txt | ./bin/ffm_train -m model.txt -field_config config.txt -dim 1,1,8 -core 4
```

预测:
```bash
cat test.txt | ./bin/ffm_predict -m model.txt -field_config config.txt -dim 8 -out pred.txt -core 4
```

### 3. 大数字特征（自动提取域ID）

如果你的特征是大数字（>= 1000000）且遵循高32位=域ID的编码规范：

样本:
```
1 51539607553:1 55834574849:1 60129542145:0.5
```

**无需配置**，自动提取：
- `51539607553` → `field_12` (域ID=12)
- `55834574849` → `field_13` (域ID=13)  
- `60129542145` → `field_14` (域ID=14)

### 4. 运行示例

```bash
# 快速演示
sh scripts/demo.sh

# 完整测试
sh scripts/test.sh

# 数字特征示例
sh example_numeric_field.sh
```

### 5. 重要提示

⚠️ **FM格式必须提供配置文件！**

```bash
# 错误❌ - FM格式但没有配置文件
cat data.txt | ./bin/ffm_train -m model.txt -dim 1,1,8

# 正确✅ - 提供配置文件
cat data.txt | ./bin/ffm_train -m model.txt -field_config config.txt -dim 1,1,8

# 或者使用FFM格式✅
# 样本: 1 field:feature:value
```

### 6. 查看详细文档

- 域配置: `docs/FIELD_CONFIG.md`
- 样本格式: `docs/SAMPLE_FORMAT.md`
- 完整更新: `docs/UPDATE_SUMMARY.md`

### 7. 常见问题

**Q: 报错 "FM format requires field config file"?**  
A: FM格式必须提供 `-field_config` 参数

**Q: 报错 "feature 'xxx' not found in config"?**  
A: 在配置文件中添加该特征的映射

**Q: 大数字特征需要配置吗？**  
A: 不需要！>= 1000000 的数字特征自动提取域ID

---

就这么简单！开始使用 alphaFFM-go 吧！ 🚀

