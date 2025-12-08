package model

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
	"sync"

	"github.com/xiongle/alphaFFM-go/pkg/simd"
	"github.com/xiongle/alphaFFM-go/pkg/utils"
)

const BiasFeatureName = "bias"

// FFMModelUnit FFM模型单元（针对每个特征）
// FFM的核心特点：每个特征针对不同的field有不同的隐向量
type FFMModelUnit struct {
	Wi   float64              // 一阶权重
	WNi  float64              // w的n参数（累积梯度平方和）
	WZi  float64              // w的z参数
	
	// FFM核心：针对每个field的隐向量映射
	ViMap  map[string][]float64 // field -> 隐向量
	VNiMap map[string][]float64 // field -> v的n参数
	VZiMap map[string][]float64 // field -> v的z参数
	
	mu sync.RWMutex // 保护 map 的并发访问
}

// NewFFMModelUnit 创建FFM模型单元
func NewFFMModelUnit(factorNum int, mean, stdev float64) *FFMModelUnit {
	return &FFMModelUnit{
		Wi:     0.0,
		WNi:    0.0,
		WZi:    0.0,
		ViMap:  make(map[string][]float64),
		VNiMap: make(map[string][]float64),
		VZiMap: make(map[string][]float64),
	}
}

// GetOrInitVi 获取或初始化针对特定field的隐向量
func (u *FFMModelUnit) GetOrInitVi(field string, factorNum int, mean, stdev float64) []float64 {
	// 先用读锁尝试获取
	u.mu.RLock()
	vi, exists := u.ViMap[field]
	u.mu.RUnlock()
	
	if exists {
		return vi
	}
	
	// 需要初始化，使用写锁
	u.mu.Lock()
	defer u.mu.Unlock()
	
	// 双重检查
	if vi, exists := u.ViMap[field]; exists {
		return vi
	}
	
	// 初始化新的隐向量
	vi = make([]float64, factorNum)
	vni := make([]float64, factorNum)
	vzi := make([]float64, factorNum)
	
	for f := 0; f < factorNum; f++ {
		vi[f] = utils.GaussianWithParams(mean, stdev)
		vni[f] = 0.0
		vzi[f] = 0.0
	}
	
	u.ViMap[field] = vi
	u.VNiMap[field] = vni
	u.VZiMap[field] = vzi
	
	return vi
}

// IsNonZero 判断是否非零
func (u *FFMModelUnit) IsNonZero() bool {
	if u.Wi != 0.0 {
		return true
	}
	u.mu.RLock()
	defer u.mu.RUnlock()
	
	for _, vi := range u.ViMap {
		for _, v := range vi {
			if v != 0.0 {
				return true
			}
		}
	}
	return false
}

// String 转为字符串（用于输出模型）
func (u *FFMModelUnit) String(fieldNames []string, factorNum int) string {
	u.mu.RLock()
	defer u.mu.RUnlock()
	
	parts := []string{fmt.Sprintf("%.6g", u.Wi)}

	// 按field顺序输出vi
	for _, field := range fieldNames {
		if vi, exists := u.ViMap[field]; exists {
			for _, v := range vi {
				parts = append(parts, fmt.Sprintf("%.6g", v))
			}
		} else {
			// field不存在，输出零向量
			for f := 0; f < factorNum; f++ {
				parts = append(parts, "0")
			}
		}
	}

	// w_ni, w_zi
	parts = append(parts, fmt.Sprintf("%.6g", u.WNi))
	parts = append(parts, fmt.Sprintf("%.6g", u.WZi))

	// 按field顺序输出v_ni
	for _, field := range fieldNames {
		if vni, exists := u.VNiMap[field]; exists {
			for _, vn := range vni {
				parts = append(parts, fmt.Sprintf("%.6g", vn))
			}
		} else {
			for f := 0; f < factorNum; f++ {
				parts = append(parts, "0")
			}
		}
	}

	// 按field顺序输出v_zi
	for _, field := range fieldNames {
		if vzi, exists := u.VZiMap[field]; exists {
			for _, vz := range vzi {
				parts = append(parts, fmt.Sprintf("%.6g", vz))
			}
		} else {
			for f := 0; f < factorNum; f++ {
				parts = append(parts, "0")
			}
		}
	}

	return strings.Join(parts, " ")
}

// FFMModel FFM模型
type FFMModel struct {
	MuBias     *FFMModelUnit
	MuMap      map[string]*FFMModelUnit
	FactorNum  int
	InitMean   float64
	InitStdev  float64
	FieldNames []string // 所有field的名称列表（用于模型序列化）
	mu         sync.RWMutex
}

// NewFFMModel 创建FFM模型
func NewFFMModel(factorNum int, mean, stdev float64) *FFMModel {
	return &FFMModel{
		MuMap:      make(map[string]*FFMModelUnit),
		FactorNum:  factorNum,
		InitMean:   mean,
		InitStdev:  stdev,
		FieldNames: make([]string, 0),
	}
}

// GetOrInitModelUnit 获取或初始化模型单元
func (m *FFMModel) GetOrInitModelUnit(feature string) *FFMModelUnit {
	m.mu.RLock()
	unit, exists := m.MuMap[feature]
	m.mu.RUnlock()

	if exists {
		return unit
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// 双重检查
	if unit, exists := m.MuMap[feature]; exists {
		return unit
	}

	unit = NewFFMModelUnit(m.FactorNum, m.InitMean, m.InitStdev)
	m.MuMap[feature] = unit
	return unit
}

// GetOrInitModelUnitBias 获取或初始化bias单元
func (m *FFMModel) GetOrInitModelUnitBias() *FFMModelUnit {
	if m.MuBias == nil {
		m.mu.Lock()
		if m.MuBias == nil {
			m.MuBias = NewFFMModelUnit(0, m.InitMean, m.InitStdev)
		}
		m.mu.Unlock()
	}
	return m.MuBias
}

// RegisterField 注册field（用于模型序列化）
func (m *FFMModel) RegisterField(field string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	// 检查是否已存在
	for _, f := range m.FieldNames {
		if f == field {
			return
		}
	}
	m.FieldNames = append(m.FieldNames, field)
}

// Predict FFM预测
// FFM预测公式：y = w0 + Σwi*xi + ΣΣ<vi,fj, vj,fi>*xi*xj
// 其中 vi,fj 表示特征i针对特征j的field的隐向量
func (m *FFMModel) Predict(x []struct{ Field, Feature string; Value float64 }, bias float64, theta []*FFMModelUnit) float64 {
	result := bias

	// 一阶项
	for i := 0; i < len(x); i++ {
		result += theta[i].Wi * x[i].Value
	}

	// 二阶交互项（FFM）
	// 对于每一对特征(i,j)，计算 <vi,fj, vj,fi> * xi * xj
	for i := 0; i < len(x); i++ {
		for j := i + 1; j < len(x); j++ {
			// 获取特征i针对特征j的field的隐向量
			vi := theta[i].GetOrInitVi(x[j].Field, m.FactorNum, m.InitMean, m.InitStdev)
			// 获取特征j针对特征i的field的隐向量
			vj := theta[j].GetOrInitVi(x[i].Field, m.FactorNum, m.InitMean, m.InitStdev)
			
			// 计算内积
			innerProduct := 0.0
			for f := 0; f < m.FactorNum; f++ {
				innerProduct += vi[f] * vj[f]
			}
			
			result += innerProduct * x[i].Value * x[j].Value
		}
	}

	return result
}

// PredictSIMD FFM预测（使用SIMD优化）
func (m *FFMModel) PredictSIMD(x []struct{ Field, Feature string; Value float64 }, bias float64, theta []*FFMModelUnit, ops simd.VectorOps) float64 {
	result := bias
	xLen := len(x)
	
	if xLen == 0 {
		return result
	}

	// 一阶项
	for i := 0; i < xLen; i++ {
		result += theta[i].Wi * x[i].Value
	}

	// 二阶交互项（FFM）- 使用SIMD优化
	for i := 0; i < xLen; i++ {
		for j := i + 1; j < xLen; j++ {
			vi := theta[i].GetOrInitVi(x[j].Field, m.FactorNum, m.InitMean, m.InitStdev)
			vj := theta[j].GetOrInitVi(x[i].Field, m.FactorNum, m.InitMean, m.InitStdev)
			
			// 使用SIMD计算内积
			innerProduct := ops.DotProduct(vi, vj)
			result += innerProduct * x[i].Value * x[j].Value
		}
	}

	return result
}

// LoadModel 加载模型
func (m *FFMModel) LoadModel(modelPath, modelFormat string) error {
	if modelFormat == "txt" {
		return m.loadTxtModel(modelPath)
	} else if modelFormat == "bin" {
		return fmt.Errorf("binary format not yet implemented for FFM")
	}
	return fmt.Errorf("unsupported model format: %s", modelFormat)
}

// loadTxtModel 加载文本模型
func (m *FFMModel) loadTxtModel(modelPath string) error {
	file, err := os.Open(modelPath)
	if err != nil {
		return err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)

	// 读取第一行：field列表
	if !scanner.Scan() {
		return fmt.Errorf("empty model file")
	}
	firstLine := strings.Fields(scanner.Text())
	if len(firstLine) < 2 || firstLine[0] != "FIELDS" {
		return fmt.Errorf("invalid model format: missing FIELDS header")
	}
	m.FieldNames = firstLine[1:]
	numFields := len(m.FieldNames)

	// 读取bias行
	if !scanner.Scan() {
		return fmt.Errorf("missing bias line")
	}
	parts := strings.Fields(scanner.Text())
	if len(parts) != 4 {
		return fmt.Errorf("invalid bias line format")
	}

	m.MuBias = NewFFMModelUnit(0, m.InitMean, m.InitStdev)
	m.MuBias.Wi, err = strconv.ParseFloat(parts[1], 64)
	if err != nil {
		return err
	}
	m.MuBias.WNi, err = strconv.ParseFloat(parts[2], 64)
	if err != nil {
		return err
	}
	m.MuBias.WZi, err = strconv.ParseFloat(parts[3], 64)
	if err != nil {
		return err
	}

	// 读取特征行
	expectedLen := 1 + 1 + numFields*m.FactorNum + 2 + numFields*m.FactorNum*2
	for scanner.Scan() {
		parts := strings.Fields(scanner.Text())
		if len(parts) != expectedLen {
			return fmt.Errorf("invalid feature line format: expected %d fields, got %d", expectedLen, len(parts))
		}

		feature := parts[0]
		unit := NewFFMModelUnit(m.FactorNum, m.InitMean, m.InitStdev)

		unit.Wi, err = strconv.ParseFloat(parts[1], 64)
		if err != nil {
			return err
		}

		// 解析每个field的vi
		idx := 2
		for _, field := range m.FieldNames {
			vi := make([]float64, m.FactorNum)
			for f := 0; f < m.FactorNum; f++ {
				vi[f], err = strconv.ParseFloat(parts[idx], 64)
				if err != nil {
					return err
				}
				idx++
			}
			unit.ViMap[field] = vi
		}

		// w_n, w_z
		unit.WNi, err = strconv.ParseFloat(parts[idx], 64)
		if err != nil {
			return err
		}
		idx++
		unit.WZi, err = strconv.ParseFloat(parts[idx], 64)
		if err != nil {
			return err
		}
		idx++

		// 解析每个field的v_ni
		for _, field := range m.FieldNames {
			vni := make([]float64, m.FactorNum)
			for f := 0; f < m.FactorNum; f++ {
				vni[f], err = strconv.ParseFloat(parts[idx], 64)
				if err != nil {
					return err
				}
				idx++
			}
			unit.VNiMap[field] = vni
		}

		// 解析每个field的v_zi
		for _, field := range m.FieldNames {
			vzi := make([]float64, m.FactorNum)
			for f := 0; f < m.FactorNum; f++ {
				vzi[f], err = strconv.ParseFloat(parts[idx], 64)
				if err != nil {
					return err
				}
				idx++
			}
			unit.VZiMap[field] = vzi
		}

		m.MuMap[feature] = unit
	}

	return scanner.Err()
}

// OutputModel 输出模型
func (m *FFMModel) OutputModel(modelPath, modelFormat string) error {
	if modelFormat == "txt" {
		return m.outputTxtModel(modelPath)
	} else if modelFormat == "bin" {
		return fmt.Errorf("binary format not yet implemented for FFM")
	}
	return fmt.Errorf("unsupported model format: %s", modelFormat)
}

// outputTxtModel 输出文本模型
func (m *FFMModel) outputTxtModel(modelPath string) error {
	// 检查是否有有效数据
	if m.MuBias == nil || len(m.FieldNames) == 0 {
		return fmt.Errorf("no valid samples processed, cannot output model")
	}

	file, err := os.Create(modelPath)
	if err != nil {
		return err
	}
	defer file.Close()

	writer := bufio.NewWriter(file)
	defer writer.Flush()

	// 输出field列表
	fmt.Fprintf(writer, "FIELDS %s\n", strings.Join(m.FieldNames, " "))

	// 输出bias
	fmt.Fprintf(writer, "%s %.6g %.6g %.6g\n", BiasFeatureName, m.MuBias.Wi, m.MuBias.WNi, m.MuBias.WZi)

	// 输出特征
	for feature, unit := range m.MuMap {
		fmt.Fprintf(writer, "%s %s\n", feature, unit.String(m.FieldNames, m.FactorNum))
	}

	return nil
}

// PredictModel FFM预测模型（简化版，只包含wi和vi）
type PredictModel struct {
	MuBias     *PredictModelUnit
	MuMap      map[string]*PredictModelUnit
	FactorNum  int
	FieldNames []string
}

// PredictModelUnit FFM预测模型单元
type PredictModelUnit struct {
	Wi    float64
	ViMap map[string][]float64 // field -> 隐向量
}

// NewPredictModel 创建预测模型
func NewPredictModel(factorNum int) *PredictModel {
	return &PredictModel{
		MuMap:      make(map[string]*PredictModelUnit),
		FactorNum:  factorNum,
		FieldNames: make([]string, 0),
	}
}

// GetOrInitVi 获取或初始化针对特定field的隐向量（预测时不初始化新值，返回零向量）
func (u *PredictModelUnit) GetOrInitVi(field string, factorNum int) []float64 {
	if vi, exists := u.ViMap[field]; exists {
		return vi
	}
	// 预测时返回零向量
	return make([]float64, factorNum)
}

// GetScore 计算预测得分（包含sigmoid）
func (m *PredictModel) GetScore(x []struct{ Field, Feature string; Value float64 }, bias float64) float64 {
	result := bias

	// 一阶项
	for i := 0; i < len(x); i++ {
		if unit, ok := m.MuMap[x[i].Feature]; ok {
			result += unit.Wi * x[i].Value
		}
	}

	// 二阶交互项（FFM）
	for i := 0; i < len(x); i++ {
		unitI, okI := m.MuMap[x[i].Feature]
		if !okI {
			continue
		}
		
		for j := i + 1; j < len(x); j++ {
			unitJ, okJ := m.MuMap[x[j].Feature]
			if !okJ {
				continue
			}
			
			vi := unitI.GetOrInitVi(x[j].Field, m.FactorNum)
			vj := unitJ.GetOrInitVi(x[i].Field, m.FactorNum)
			
			innerProduct := 0.0
			for f := 0; f < m.FactorNum; f++ {
				innerProduct += vi[f] * vj[f]
			}
			
			result += innerProduct * x[i].Value * x[j].Value
		}
	}

	// Sigmoid
	return 1.0 / (1.0 + math.Exp(-result))
}

// GetScoreSIMD 计算预测得分（包含sigmoid，使用SIMD优化）
func (m *PredictModel) GetScoreSIMD(x []struct{ Field, Feature string; Value float64 }, bias float64, ops simd.VectorOps) float64 {
	result := bias

	// 一阶项
	for i := 0; i < len(x); i++ {
		if unit, ok := m.MuMap[x[i].Feature]; ok {
			result += unit.Wi * x[i].Value
		}
	}

	// 二阶交互项（FFM）- 使用SIMD优化
	for i := 0; i < len(x); i++ {
		unitI, okI := m.MuMap[x[i].Feature]
		if !okI {
			continue
		}
		
		for j := i + 1; j < len(x); j++ {
			unitJ, okJ := m.MuMap[x[j].Feature]
			if !okJ {
				continue
			}
			
			vi := unitI.GetOrInitVi(x[j].Field, m.FactorNum)
			vj := unitJ.GetOrInitVi(x[i].Field, m.FactorNum)
			
			innerProduct := ops.DotProduct(vi, vj)
			result += innerProduct * x[i].Value * x[j].Value
		}
	}

	// Sigmoid
	return 1.0 / (1.0 + math.Exp(-result))
}

// LoadModel 加载模型
func (m *PredictModel) LoadModel(modelPath, modelFormat string) error {
	if modelFormat == "txt" {
		return m.loadTxtModel(modelPath)
	} else if modelFormat == "bin" {
		return fmt.Errorf("binary format not yet implemented for FFM")
	}
	return fmt.Errorf("unsupported model format: %s", modelFormat)
}

// loadTxtModel 加载文本模型
func (m *PredictModel) loadTxtModel(modelPath string) error {
	file, err := os.Open(modelPath)
	if err != nil {
		return err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)

	// 读取field列表
	if !scanner.Scan() {
		return fmt.Errorf("empty model file")
	}
	firstLine := strings.Fields(scanner.Text())
	if len(firstLine) < 2 || firstLine[0] != "FIELDS" {
		return fmt.Errorf("invalid model format: missing FIELDS header")
	}
	m.FieldNames = firstLine[1:]
	numFields := len(m.FieldNames)

	// 读取bias
	if !scanner.Scan() {
		return fmt.Errorf("missing bias line")
	}
	parts := strings.Fields(scanner.Text())
	if len(parts) != 4 {
		return fmt.Errorf("invalid bias line")
	}

	m.MuBias = &PredictModelUnit{ViMap: make(map[string][]float64)}
	m.MuBias.Wi, err = strconv.ParseFloat(parts[1], 64)
	if err != nil {
		return err
	}

	// 读取特征
	expectedLen := 1 + 1 + numFields*m.FactorNum + 2 + numFields*m.FactorNum*2
	for scanner.Scan() {
		parts := strings.Fields(scanner.Text())
		if len(parts) != expectedLen {
			continue // 跳过格式错误的行
		}

		feature := parts[0]
		unit := &PredictModelUnit{ViMap: make(map[string][]float64)}

		unit.Wi, err = strconv.ParseFloat(parts[1], 64)
		if err != nil {
			continue
		}

		// 解析每个field的vi
		idx := 2
		isNonZero := unit.Wi != 0.0
		for _, field := range m.FieldNames {
			vi := make([]float64, m.FactorNum)
			for f := 0; f < m.FactorNum; f++ {
				vi[f], err = strconv.ParseFloat(parts[idx], 64)
				if err != nil {
					vi[f] = 0.0
				}
				if vi[f] != 0.0 {
					isNonZero = true
				}
				idx++
			}
			unit.ViMap[field] = vi
		}

		// 只加载非零特征
		if isNonZero {
			m.MuMap[feature] = unit
		}
	}

	return scanner.Err()
}

