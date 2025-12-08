package model

import (
	"bufio"
	"fmt"
	"os"
	"sync"

	"github.com/xiongle/alphaFFM-go/pkg/config"
	"github.com/xiongle/alphaFFM-go/pkg/sample"
	"github.com/xiongle/alphaFFM-go/pkg/simd"
)

// PredictorOption 预测选项
type PredictorOption struct {
	ModelPath       string
	ModelFormat     string
	PredictPath     string
	ModelNumberType string
	ThreadsNum      int
	FactorNum       int
	SIMDType        simd.VectorOpsType // SIMD优化类型
	FieldConfigPath string             // 域配置文件路径
}

// NewPredictorOption 创建默认预测选项
func NewPredictorOption() *PredictorOption {
	return &PredictorOption{
		FactorNum:       8,
		ThreadsNum:      1,
		ModelFormat:     "txt",
		ModelNumberType: "double",
		SIMDType:        simd.VectorOpsScalar, // 默认不使用SIMD
	}
}

// FFMPredictor FFM预测器
type FFMPredictor struct {
	model       *PredictModel
	opt         *PredictorOption
	outFile     *os.File
	outMu       sync.Mutex
	simdOps     simd.VectorOps      // SIMD运算实例
	useSIMD     bool                // 是否使用SIMD
	fieldConfig *config.FieldConfig // 域配置
}

// NewFFMPredictor 创建预测器
func NewFFMPredictor(opt *PredictorOption) (*FFMPredictor, error) {
	p := &FFMPredictor{
		model: NewPredictModel(opt.FactorNum),
		opt:   opt,
	}

	// 加载域配置文件
	if opt.FieldConfigPath != "" {
		fieldConfig := config.NewFieldConfig()
		
		// 尝试JSON格式
		if err := fieldConfig.LoadFromJSON(opt.FieldConfigPath); err != nil {
			// 尝试文本格式
			if err2 := fieldConfig.LoadFromText(opt.FieldConfigPath); err2 != nil {
				fmt.Printf("Warning: failed to load field config from %s (JSON: %v, Text: %v), using auto mode\n", 
					opt.FieldConfigPath, err, err2)
			} else {
				// 文本格式加载成功
				fieldConfig.Mode = "config"
				if err := fieldConfig.Validate(); err != nil {
					fmt.Printf("Warning: invalid field config: %v, using auto mode\n", err)
				} else {
					p.fieldConfig = fieldConfig
					fmt.Printf("Loaded field config from %s (text format, %d mappings)\n", 
						opt.FieldConfigPath, len(fieldConfig.FeatureToField))
				}
			}
		} else {
			// JSON格式加载成功
			if err := fieldConfig.Validate(); err != nil {
				fmt.Printf("Warning: invalid field config: %v, using auto mode\n", err)
			} else {
				p.fieldConfig = fieldConfig
				fmt.Printf("Loaded field config from %s (JSON format, mode: %s, %d mappings)\n", 
					opt.FieldConfigPath, fieldConfig.Mode, len(fieldConfig.FeatureToField))
			}
		}
	}

	// 初始化SIMD
	if opt.SIMDType != simd.VectorOpsScalar {
		ops, err := simd.NewVectorOps(opt.SIMDType)
		if err != nil {
			fmt.Printf("Warning: SIMD initialization failed, falling back to scalar: %v\n", err)
			p.simdOps = simd.NewScalarOps()
			p.useSIMD = false
		} else {
			p.simdOps = ops
			p.useSIMD = true
			fmt.Printf("SIMD enabled: %s\n", ops.Name())
		}
	} else {
		p.simdOps = simd.NewScalarOps()
		p.useSIMD = false
	}

	// 加载模型
	fmt.Println("load model...")
	if err := p.model.LoadModel(opt.ModelPath, opt.ModelFormat); err != nil {
		return nil, fmt.Errorf("load model error: %v", err)
	}
	fmt.Println("model loading finished")

	// 打开输出文件
	f, err := os.Create(opt.PredictPath)
	if err != nil {
		return nil, fmt.Errorf("open output file error: %v", err)
	}
	p.outFile = f

	return p, nil
}

// RunTask 处理一批数据
func (p *FFMPredictor) RunTask(dataBuffer []string) error {
	results := make([]string, len(dataBuffer))

	for i, line := range dataBuffer {
		var s *sample.FFMSample
		var err error
		
		// 使用配置文件解析样本
		if p.fieldConfig != nil {
			s, err = sample.ParseSampleWithConfig(line, p.fieldConfig)
		} else {
			s, err = sample.ParseSample(line)
		}
		
		if err != nil {
			fmt.Printf("Warning: skip invalid sample: %v\n", err)
			continue
		}

		// 转换特征格式
		xForPredict := make([]struct{ Field, Feature string; Value float64 }, len(s.X))
		for j := 0; j < len(s.X); j++ {
			xForPredict[j].Field = s.X[j].Field
			xForPredict[j].Feature = s.X[j].Feature
			xForPredict[j].Value = s.X[j].Value
		}

		var score float64
		if p.useSIMD {
			score = p.model.GetScoreSIMD(xForPredict, p.model.MuBias.Wi, p.simdOps)
		} else {
			score = p.model.GetScore(xForPredict, p.model.MuBias.Wi)
		}
		results[i] = fmt.Sprintf("%d %.6g", s.Y, score)
	}

	// 写入结果
	p.outMu.Lock()
	defer p.outMu.Unlock()

	writer := bufio.NewWriter(p.outFile)
	for _, result := range results {
		if result != "" {
			fmt.Fprintln(writer, result)
		}
	}
	writer.Flush()

	return nil
}

// Close 关闭预测器
func (p *FFMPredictor) Close() error {
	if p.outFile != nil {
		return p.outFile.Close()
	}
	return nil
}

