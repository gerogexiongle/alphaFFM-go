package config

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// FieldConfig 域配置
type FieldConfig struct {
	// Mode 模式: "auto" - 自动从特征名提取域, "explicit" - 样本显示指定域, "config" - 使用配置文件映射
	Mode string `json:"mode"`
	
	// FeatureToField 特征到域的映射
	// key: 特征前缀或完整特征名
	// value: 域名
	FeatureToField map[string]string `json:"feature_to_field"`
	
	// DefaultField 默认域名（当特征无法匹配到任何规则时使用）
	DefaultField string `json:"default_field"`
	
	// UsePrefix 是否使用前缀匹配（true: 前缀匹配, false: 完全匹配）
	UsePrefix bool `json:"use_prefix"`
	
	// NumericFieldThreshold 数字特征阈值，大于此值时自动提取高32位作为域ID
	// 默认值: 4294967296 (2^32)
	NumericFieldThreshold uint64 `json:"numeric_field_threshold"`
	
	// NumericFieldPrefix 数字域的前缀（如 "field_"），生成的域名格式为 prefix + 域ID
	NumericFieldPrefix string `json:"numeric_field_prefix"`
}

// NewFieldConfig 创建默认配置
func NewFieldConfig() *FieldConfig {
	return &FieldConfig{
		Mode:                  "config",
		FeatureToField:        make(map[string]string),
		DefaultField:          "",
		UsePrefix:             true,
		NumericFieldThreshold: 1000000,
		NumericFieldPrefix:    "field_",
	}
}

// LoadFromJSON 从JSON文件加载配置
func (c *FieldConfig) LoadFromJSON(path string) error {
	file, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("failed to open config file: %v", err)
	}
	defer file.Close()

	decoder := json.NewDecoder(file)
	if err := decoder.Decode(c); err != nil {
		return fmt.Errorf("failed to parse config file: %v", err)
	}

	return nil
}

// LoadFromText 从文本文件加载配置
// 格式: feature_prefix field_name
// 例如:
//   sex user
//   age user
//   f1 item
//   f2 item
func (c *FieldConfig) LoadFromText(path string) error {
	file, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("failed to open config file: %v", err)
	}
	defer file.Close()

	c.FeatureToField = make(map[string]string)
	scanner := bufio.NewScanner(file)
	lineNum := 0

	for scanner.Scan() {
		lineNum++
		line := strings.TrimSpace(scanner.Text())
		
		// 跳过空行和注释
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		parts := strings.Fields(line)
		if len(parts) < 2 {
			return fmt.Errorf("invalid format at line %d: expected 'feature field'", lineNum)
		}

		featurePrefix := parts[0]
		fieldName := parts[1]
		c.FeatureToField[featurePrefix] = fieldName
	}

	if err := scanner.Err(); err != nil {
		return fmt.Errorf("error reading config file: %v", err)
	}

	return nil
}

// SaveToJSON 保存配置到JSON文件
func (c *FieldConfig) SaveToJSON(path string) error {
	file, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("failed to create config file: %v", err)
	}
	defer file.Close()

	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(c); err != nil {
		return fmt.Errorf("failed to write config file: %v", err)
	}

	return nil
}

// GetFieldForFeature 根据特征名获取对应的域名
// 返回: (域名, 错误)
// 三种处理规则:
// 1. 大数字特征 (>= threshold): 自动提取高32位作为域ID
// 2. 小特征: 必须在配置文件中找到映射，否则报错
// 3. explicit模式: 返回空（使用样本中的域名）
func (c *FieldConfig) GetFieldForFeature(feature string) (string, error) {
	// 如果是 explicit 模式，不进行映射（样本中已包含域信息）
	if c.Mode == "explicit" {
		return "", nil
	}

	// 规则1: 检查是否是大数字特征（高32位编码域ID）
	// 只有全数字且大于等于阈值时才自动提取
	if numFeature, err := strconv.ParseUint(feature, 10, 64); err == nil {
		if numFeature >= c.NumericFieldThreshold {
			// 提取高32位作为域ID
			fieldID := uint32(numFeature >> 32)
			return fmt.Sprintf("%s%d", c.NumericFieldPrefix, fieldID), nil
		}
	}

	// 规则2: 小特征必须在配置文件中找到映射
	if c.UsePrefix {
		// 前缀匹配：按长度从长到短尝试匹配
		maxLen := 0
		matchedField := ""
		for prefix, field := range c.FeatureToField {
			if strings.HasPrefix(feature, prefix) && len(prefix) > maxLen {
				maxLen = len(prefix)
				matchedField = field
			}
		}
		if matchedField != "" {
			return matchedField, nil
		}
	} else {
		// 完全匹配
		if field, ok := c.FeatureToField[feature]; ok {
			return field, nil
		}
	}

	// 使用默认域名
	if c.DefaultField != "" {
		return c.DefaultField, nil
	}

	// 小特征必须有配置，否则报错
	return "", fmt.Errorf("feature '%s' not found in config and not a large numeric feature (>= %d)", 
		feature, c.NumericFieldThreshold)
}

// extractFieldFromFeature 从特征名自动提取域名
func (c *FieldConfig) extractFieldFromFeature(feature string) string {
	// 按下划线分割
	parts := strings.Split(feature, "_")
	if len(parts) > 1 {
		return parts[0]
	}
	// 默认：每个特征自成一个域
	return feature
}

// Validate 验证配置
func (c *FieldConfig) Validate() error {
	validModes := map[string]bool{
		"explicit": true,
		"config":   true,
	}

	if !validModes[c.Mode] {
		return fmt.Errorf("invalid mode: %s (must be one of: explicit, config)", c.Mode)
	}

	if c.Mode == "config" && len(c.FeatureToField) == 0 {
		return fmt.Errorf("config mode requires feature_to_field mapping")
	}

	return nil
}

