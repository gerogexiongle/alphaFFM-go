# alphaFFM-go 项目优化总结

## 更新日期
2024-12-08

## 更新概述

成功为 alphaFFM-go 项目实现了灵活的域名映射机制，支持三种严格的样本格式处理模式，完美兼容 FM 格式样本输入，同时支持业务中常见的大数字特征编码规范。

---

## 核心更新

### 1. 新增配置文件包 (`pkg/config`)

创建了 `field_config.go`，实现特征到域的灵活映射：

**主要功能**:
- 支持文本和 JSON 两种配置格式
- 前缀匹配和完全匹配两种模式
- 大数字特征自动提取（高32位作为域ID）
- 严格的错误检查机制

**关键特性**:
```go
type FieldConfig struct {
    Mode                  string              // 模式: explicit, config
    FeatureToField        map[string]string   // 特征到域的映射
    DefaultField          string              // 默认域名
    UsePrefix             bool                // 前缀匹配
    NumericFieldThreshold uint64              // 数字特征阈值 (默认: 1000000)
    NumericFieldPrefix    string              // 数字域前缀 (默认: "field_")
}
```

### 2. 修改样本解析 (`pkg/sample`)

**更新内容**:
- 新增 `ParseSampleWithConfig()` 函数
- FM 格式（`label feature:value`）必须提供配置文件
- 支持 FFM 格式（`label field:feature:value`）不需要配置
- 严格的错误提示

**关键改进**:
```go
// FM格式必须提供配置文件
if fieldConfig == nil {
    return nil, fmt.Errorf("FM format requires field config file")
}
```

### 3. 更新训练和预测器

**trainer 和 predictor 更新**:
- 新增 `FieldConfigPath` 参数
- 自动加载并验证配置文件
- 支持 JSON 和文本两种格式
- 详细的加载日志

### 4. 命令行工具更新

**新增参数**:
```bash
-field_config <config_path>: 域映射配置文件（JSON或文本格式）
```

**使用示例**:
```bash
# 训练
cat train.txt | ./bin/ffm_train -m model.txt -field_config config.txt -dim 1,1,8

# 预测
cat test.txt | ./bin/ffm_predict -m model.txt -field_config config.txt -dim 8 -out pred.txt
```

---

## 三种严格模式

### 模式1: 显式域名 (FFM 格式)

**格式**: `label field:feature:value`

**示例**:
```
1 user:sex:1 user:age:0.3 item:f1:1
```

**特点**:
- ✅ 域名在样本中显式指定
- ✅ 不需要配置文件
- ✅ 最高灵活性

### 模式2: 小特征 + 配置文件

**格式**: `label feature:value`

**特征类型**: 字符串或小数字（< 1000000）

**示例样本**:
```
1 sex:1 age:0.3 f1:1 f2:0.4
```

**配置文件**:
```
sex user
age user
f1 item
f2 item
```

**特点**:
- ⚠️ **必须提供配置文件，否则报错**
- ⚠️ 特征必须在配置中找到映射，否则报错
- ✅ 样本文件简洁
- ✅ 灵活控制域划分

### 模式3: 大数字特征（自动提取）

**格式**: `label feature:value`

**特征类型**: 大数字（>= 1000000）

**编码规则**: 
```
特征编码 = (域ID << 32) | 特征ID
高32位 = 域ID
低32位 = 特征ID
```

**示例**:
```
特征: 51539607553 (0x0000000C00000001)
域ID: 12
特征ID: 1
域名: field_12
```

**特点**:
- ✅ 自动提取高32位作为域ID
- ✅ 不需要配置，不报错
- ✅ 支持海量域（2^32个）
- ✅ 完美匹配业务编码规范

### 混合模式（推荐）

可以在同一样本中混用模式2和模式3：

**示例**:
```
1 51539607553:1 55834574849:1 sex:1 age:0.3
```

**处理结果**:
- `51539607553` → `field_12` (自动提取)
- `55834574849` → `field_13` (自动提取)
- `sex`, `age` → `user` (配置映射)

---

## 配置文件格式

### 文本格式（推荐）

```
# 注释行
feature_prefix field_name

# 用户特征
sex user
age user

# 商品特征
f1 item
f2 item
```

### JSON 格式

```json
{
  "mode": "config",
  "use_prefix": true,
  "default_field": "",
  "numeric_field_threshold": 1000000,
  "numeric_field_prefix": "field_",
  "feature_to_field": {
    "sex": "user",
    "age": "user",
    "f1": "item"
  }
}
```

---

## 错误处理

### 1. FM格式未提供配置文件
```
错误: FM format (feature:value) requires field config file, 
      use -field_config option or use FFM format (field:feature:value)
```

### 2. 小特征未在配置中
```
错误: feature 'unknown' not found in config and not a large numeric feature (>= 1000000)
```

### 3. 没有有效样本
```
错误: no valid samples processed, cannot output model
```

---

## 示例脚本

项目提供了完整的示例和测试脚本：

### 1. `scripts/demo.sh` - 基础演示
- 自动创建临时配置文件
- 演示完整的训练和预测流程
- 适合快速上手

### 2. `scripts/test.sh` - 完整测试
- 测试所有功能模块
- 多线程测试
- 不同维度测试
- 参数测试

### 3. `example_with_config.sh` - 配置文件模式示例
- 展示配置文件的使用
- FM格式样本处理

### 4. `example_numeric_field.sh` - 数字特征示例
- 展示大数字特征自动提取
- 混合模式处理

### 5. `test_strict_three_modes.sh` - 三种模式测试
- 完整测试三种严格模式
- 错误处理验证

---

## 文档更新

### 新增文档

1. **docs/FIELD_CONFIG.md** - 域配置完整文档
   - 三种映射模式详解
   - 配置文件格式说明
   - 实际案例
   - 最佳实践

2. **docs/SAMPLE_FORMAT.md** - 样本格式说明
   - 三种样本格式详解
   - 使用方法
   - 错误排查

3. **docs/WHY_DEMO_WORKS.md** - 技术说明
   - 解释原有demo为何能工作
   - 模式对比

### 更新文档

1. **README.md** - 主文档更新
   - 增加配置文件模式说明
   - 更新命令行参数
   - 添加数字特征编码说明

---

## 配置文件示例

### 1. `field_config_example.txt` - 文本格式示例
完整的文本配置示例，包含注释

### 2. `field_config_example.json` - JSON格式示例
完整的JSON配置示例

### 3. `field_config_test.txt` - 测试配置
用于测试的简化配置

### 4. `field_config_numeric.txt` - 混合模式配置
支持大数字特征和小特征的混合配置

---

## 工具脚本

### `tools/extract_field_id.go`
展示大数字特征的域ID提取过程：
```bash
go run tools/extract_field_id.go
```

输出特征的二进制表示、域ID、特征ID等详细信息。

---

## 性能影响

### 优势
1. **减少参数量**: Config模式相比Auto模式可大幅减少域数量
2. **提高训练速度**: 域数量减少 → 参数减少 → 速度提升
3. **更好的泛化**: 合理的域划分有助于模型泛化

### 对比

| 模式 | 域数量 | 参数量 | 适用场景 |
|------|--------|--------|----------|
| ~~Auto~~ (已移除) | n (每个特征一个域) | O(n²×d) | - |
| Config | k (配置的域数) | O(n×k×d) | 生产环境（推荐） |
| Explicit | 样本指定 | O(n×k×d) | 完全控制 |

---

## 向后兼容性

### 破坏性变更

⚠️ **重要**: Auto 模式已被移除！

**影响**:
- 原有使用 FM 格式但不提供配置文件的代码会报错
- 必须提供配置文件或改用 FFM 格式

**迁移方案**:

1. **方案1**: 添加配置文件
```bash
# 创建配置文件
cat > config.txt <<EOF
feature1 field1
feature2 field1
feature3 field2
EOF

# 使用配置文件
cat data.txt | ./bin/ffm_train -m model.txt -field_config config.txt -dim 1,1,8
```

2. **方案2**: 改用 FFM 格式
```bash
# 样本格式从: 1 f1:1 f2:1
# 改为: 1 field1:f1:1 field1:f2:1
```

---

## 使用建议

### 1. 小规模测试
使用显式域名格式，快速验证模型效果

### 2. 生产环境
使用 Config 模式 + 文本配置文件：
- 大数字特征自动处理
- 小特征通过配置映射
- 严格错误检查，避免配置遗漏

### 3. 特征编码规范
对于大规模业务特征，建议统一使用：
```
特征ID = (域ID << 32) | 特征索引
```

### 4. 配置管理
- 将配置文件与模型一起保存
- 使用版本控制管理配置变更
- 训练和预测必须使用相同配置

---

## 测试验证

所有功能已通过完整测试：

```bash
# 运行完整测试
sh scripts/test.sh

# 运行演示
sh scripts/demo.sh

# 测试三种模式
sh test_strict_three_modes.sh

# 测试数字特征
sh example_numeric_field.sh
```

**测试结果**: ✅ 所有测试通过！

---

## 后续计划

1. 性能优化
   - BLAS SIMD 优化测试
   - 大规模数据集测试

2. 功能增强
   - 二进制配置格式支持
   - 配置文件热加载

3. 文档完善
   - 添加更多实际案例
   - 性能调优指南

---

## 总结

本次更新完美实现了您的需求：

✅ **模式1**: 显式域名 - 样本中指定域名  
✅ **模式2**: 小特征 + 配置 - 必须配置，否则报错  
✅ **模式3**: 大数字特征 - 自动提取高32位  
✅ **混合模式**: 支持模式2和模式3混合使用  
✅ **严格检查**: FM格式必须提供配置文件  
✅ **完整文档**: 详细的使用说明和示例  
✅ **示例脚本**: 多个可运行的演示脚本  

项目现在完全支持您的业务特征编码规范，既保持了样本的简洁性（FM格式），又提供了灵活的域控制能力，同时对大数字特征进行了自动化处理！

