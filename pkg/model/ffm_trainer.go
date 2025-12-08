package model

import (
	"fmt"
	"math"
	"sync"

	"github.com/xiongle/alphaFFM-go/pkg/lock"
	"github.com/xiongle/alphaFFM-go/pkg/sample"
	"github.com/xiongle/alphaFFM-go/pkg/simd"
	"github.com/xiongle/alphaFFM-go/pkg/utils"
)

// TrainerOption 训练选项
type TrainerOption struct {
	ModelPath           string
	ModelFormat         string
	InitModelPath       string
	InitialModelFormat  string
	ModelNumberType     string
	InitMean            float64
	InitStdev           float64
	WAlpha              float64
	WBeta               float64
	WL1                 float64
	WL2                 float64
	VAlpha              float64
	VBeta               float64
	VL1                 float64
	VL2                 float64
	ThreadsNum          int
	FactorNum           int
	K0                  bool
	K1                  bool
	BInit               bool
	ForceVSparse        bool
	SIMDType            simd.VectorOpsType // SIMD优化类型
}

// NewTrainerOption 创建默认训练选项
func NewTrainerOption() *TrainerOption {
	return &TrainerOption{
		K0:                 true,
		K1:                 true,
		FactorNum:          8,
		InitMean:           0.0,
		InitStdev:          0.1,
		WAlpha:             0.05,
		WBeta:              1.0,
		WL1:                0.1,
		WL2:                5.0,
		VAlpha:             0.05,
		VBeta:              1.0,
		VL1:                0.1,
		VL2:                5.0,
		ModelFormat:        "txt",
		InitialModelFormat: "txt",
		ThreadsNum:         1,
		BInit:              false,
		ForceVSparse:       false,
		ModelNumberType:    "double",
		SIMDType:           simd.VectorOpsScalar, // 默认不使用SIMD
	}
}

// FFMTrainer FFM训练器
type FFMTrainer struct {
	model        *FFMModel
	lockPool     *lock.LockPool
	opt          *TrainerOption
	simdOps      simd.VectorOps // SIMD运算实例
	useSIMD      bool           // 是否使用SIMD
}

// NewFFMTrainer 创建训练器
func NewFFMTrainer(opt *TrainerOption) *FFMTrainer {
	t := &FFMTrainer{
		model:    NewFFMModel(opt.FactorNum, opt.InitMean, opt.InitStdev),
		lockPool: lock.NewLockPool(),
		opt:      opt,
	}
	
	// 初始化SIMD
	if opt.SIMDType != simd.VectorOpsScalar {
		ops, err := simd.NewVectorOps(opt.SIMDType)
		if err != nil {
			fmt.Printf("Warning: SIMD initialization failed, falling back to scalar: %v\n", err)
			t.simdOps = simd.NewScalarOps()
			t.useSIMD = false
		} else {
			t.simdOps = ops
			t.useSIMD = true
			fmt.Printf("SIMD enabled: %s\n", ops.Name())
		}
	} else {
		t.simdOps = simd.NewScalarOps()
		t.useSIMD = false
	}
	
	return t
}

// RunTask 处理一批数据
func (t *FFMTrainer) RunTask(dataBuffer []string) error {
	for _, line := range dataBuffer {
		s, err := sample.ParseSample(line)
		if err != nil {
			fmt.Printf("Warning: skip invalid sample: %v\n", err)
			continue
		}
		t.train(s.Y, s.X)
	}
	return nil
}

// LoadModel 加载模型
func (t *FFMTrainer) LoadModel(modelPath, modelFormat string) error {
	return t.model.LoadModel(modelPath, modelFormat)
}

// OutputModel 输出模型
func (t *FFMTrainer) OutputModel(modelPath, modelFormat string) error {
	return t.model.OutputModel(modelPath, modelFormat)
}

// train 训练一个样本（FFM版本）
func (t *FFMTrainer) train(y int, x []sample.FeatureValue) {
	thetaBias := t.model.GetOrInitModelUnitBias()
	xLen := len(x)
	theta := make([]*FFMModelUnit, xLen)
	feaLocks := make([]*sync.Mutex, xLen+1)

	// 注册所有field
	for i := 0; i < xLen; i++ {
		t.model.RegisterField(x[i].Field)
	}

	// 获取模型单元和锁
	for i := 0; i < xLen; i++ {
		theta[i] = t.model.GetOrInitModelUnit(x[i].Feature)
		feaLocks[i] = t.lockPool.GetFeatureLock(x[i].Feature)
		
		// 初始化所有需要的field向量
		for j := 0; j < xLen; j++ {
			if i != j {
				theta[i].GetOrInitVi(x[j].Field, t.model.FactorNum, t.model.InitMean, t.model.InitStdev)
			}
		}
	}
	feaLocks[xLen] = t.lockPool.GetBiasLock()

	// 更新w（FTRL）
	for i := 0; i <= xLen; i++ {
		var mu *FFMModelUnit
		if i < xLen {
			mu = theta[i]
		} else {
			mu = thetaBias
		}

		if (i < xLen && t.opt.K1) || (i == xLen && t.opt.K0) {
			feaLocks[i].Lock()
			if math.Abs(mu.WZi) <= t.opt.WL1 {
				mu.Wi = 0.0
			} else {
				mu.Wi = -1.0 * (1.0 / (t.opt.WL2 + (t.opt.WBeta+math.Sqrt(mu.WNi))/t.opt.WAlpha)) *
					(mu.WZi - float64(utils.Sgn(mu.WZi))*t.opt.WL1)
			}
			feaLocks[i].Unlock()
		}
	}

	// 更新v（FTRL）- FFM针对每个field分别更新
	for i := 0; i < xLen; i++ {
		mu := theta[i]
		for j := 0; j < xLen; j++ {
			if i == j {
				continue
			}
			field := x[j].Field
			
			// 使用读锁安全地获取map中的向量
			mu.mu.RLock()
			vni := mu.VNiMap[field]
			vzi := mu.VZiMap[field]
			vi := mu.ViMap[field]
			mu.mu.RUnlock()
			
			for f := 0; f < t.model.FactorNum; f++ {
				feaLocks[i].Lock()
				if vni[f] > 0 {
					if t.opt.ForceVSparse && mu.Wi == 0.0 {
						vi[f] = 0.0
					} else if math.Abs(vzi[f]) <= t.opt.VL1 {
						vi[f] = 0.0
					} else {
						vi[f] = -1.0 * (1.0 / (t.opt.VL2 + (t.opt.VBeta+math.Sqrt(vni[f]))/t.opt.VAlpha)) *
							(vzi[f] - float64(utils.Sgn(vzi[f]))*t.opt.VL1)
					}
				}
				feaLocks[i].Unlock()
			}
		}
	}

	// 预测
	bias := thetaBias.Wi
	var p float64
	
	if t.useSIMD && xLen > 0 {
		p = t.predictSIMD(x, bias, theta)
	} else {
		p = t.predictScalar(x, bias, theta)
	}

	// 计算梯度系数
	mult := float64(y) * (1.0/(1.0+math.Exp(-p*float64(y))) - 1.0)

	// 更新w_n, w_z
	for i := 0; i <= xLen; i++ {
		var mu *FFMModelUnit
		var xi float64
		if i < xLen {
			mu = theta[i]
			xi = x[i].Value
		} else {
			mu = thetaBias
			xi = 1.0
		}

		if (i < xLen && t.opt.K1) || (i == xLen && t.opt.K0) {
			feaLocks[i].Lock()
			wGi := mult * xi
			wSi := (1.0 / t.opt.WAlpha) * (math.Sqrt(mu.WNi+wGi*wGi) - math.Sqrt(mu.WNi))
			mu.WZi += wGi - wSi*mu.Wi
			mu.WNi += wGi * wGi
			feaLocks[i].Unlock()
		}
	}

	// 更新v_n, v_z（FFM版本）
	if t.useSIMD && xLen > 0 {
		t.updateVGradientsSIMD(theta, feaLocks, x, mult)
	} else {
		t.updateVGradientsScalar(theta, feaLocks, x, mult)
	}
}

// predictScalar 标量版本的FFM预测
func (t *FFMTrainer) predictScalar(x []sample.FeatureValue, bias float64, theta []*FFMModelUnit) float64 {
	xLen := len(x)
	result := bias

	// 一阶项
	for i := 0; i < xLen; i++ {
		result += theta[i].Wi * x[i].Value
	}

	// 二阶交互项（FFM）
	for i := 0; i < xLen; i++ {
		for j := i + 1; j < xLen; j++ {
			// 安全地获取vi和vj
			theta[i].mu.RLock()
			vi := theta[i].ViMap[x[j].Field]
			theta[i].mu.RUnlock()
			
			theta[j].mu.RLock()
			vj := theta[j].ViMap[x[i].Field]
			theta[j].mu.RUnlock()
			
			innerProduct := 0.0
			for f := 0; f < t.model.FactorNum; f++ {
				innerProduct += vi[f] * vj[f]
			}
			
			result += innerProduct * x[i].Value * x[j].Value
		}
	}

	return result
}

// predictSIMD SIMD版本的FFM预测
func (t *FFMTrainer) predictSIMD(x []sample.FeatureValue, bias float64, theta []*FFMModelUnit) float64 {
	xLen := len(x)
	result := bias

	// 一阶项
	for i := 0; i < xLen; i++ {
		result += theta[i].Wi * x[i].Value
	}

	// 二阶交互项（FFM）- 使用SIMD优化
	for i := 0; i < xLen; i++ {
		for j := i + 1; j < xLen; j++ {
			// 安全地获取vi和vj
			theta[i].mu.RLock()
			vi := theta[i].ViMap[x[j].Field]
			theta[i].mu.RUnlock()
			
			theta[j].mu.RLock()
			vj := theta[j].ViMap[x[i].Field]
			theta[j].mu.RUnlock()
			
			innerProduct := t.simdOps.DotProduct(vi, vj)
			result += innerProduct * x[i].Value * x[j].Value
		}
	}

	return result
}

// updateVGradientsScalar 标量版本更新v的梯度（FFM版本）
func (t *FFMTrainer) updateVGradientsScalar(theta []*FFMModelUnit, feaLocks []*sync.Mutex, 
	x []sample.FeatureValue, mult float64) {
	
	xLen := len(x)
	
	// FFM梯度更新：对于特征i的field fj的隐向量
	// ∂L/∂vi,fj = mult * vj,fi * xj * xi
	for i := 0; i < xLen; i++ {
		mu := theta[i]
		xi := x[i].Value
		
		for j := 0; j < xLen; j++ {
			if i == j {
				continue
			}
			
			fieldJ := x[j].Field
			fieldI := x[i].Field
			xj := x[j].Value
			
			// 安全地获取vj针对fi的隐向量
			theta[j].mu.RLock()
			vj := theta[j].ViMap[fieldI]
			theta[j].mu.RUnlock()
			
			// 安全地获取mu的field向量
			mu.mu.RLock()
			vni := mu.VNiMap[fieldJ]
			vzi := mu.VZiMap[fieldJ]
			vi := mu.ViMap[fieldJ]
			mu.mu.RUnlock()
			
			for f := 0; f < t.model.FactorNum; f++ {
				feaLocks[i].Lock()
				vGif := mult * vj[f] * xj * xi
				vGifSqr := vGif * vGif
				vSif := (1.0 / t.opt.VAlpha) * (math.Sqrt(vni[f]+vGifSqr) - math.Sqrt(vni[f]))
				vzi[f] += vGif - vSif*vi[f]
				vni[f] += vGifSqr

				if t.opt.ForceVSparse && vni[f] > 0 && mu.Wi == 0.0 {
					vi[f] = 0.0
				}
				feaLocks[i].Unlock()
			}
		}
	}
}

// updateVGradientsSIMD SIMD版本更新v的梯度（FFM版本）
func (t *FFMTrainer) updateVGradientsSIMD(theta []*FFMModelUnit, feaLocks []*sync.Mutex, 
	x []sample.FeatureValue, mult float64) {
	
	xLen := len(x)
	invVAlpha := 1.0 / t.opt.VAlpha
	
	for i := 0; i < xLen; i++ {
		mu := theta[i]
		xi := x[i].Value
		
		for j := 0; j < xLen; j++ {
			if i == j {
				continue
			}
			
			fieldJ := x[j].Field
			fieldI := x[i].Field
			xj := x[j].Value
			
			// 安全地获取vj针对fi的隐向量
			theta[j].mu.RLock()
			vj := theta[j].ViMap[fieldI]
			theta[j].mu.RUnlock()
			
			// 安全地获取mu的field向量
			mu.mu.RLock()
			vni := mu.VNiMap[fieldJ]
			vzi := mu.VZiMap[fieldJ]
			vi := mu.ViMap[fieldJ]
			mu.mu.RUnlock()
			
			// 计算梯度系数
			gradCoef := mult * xj * xi
			
			feaLocks[i].Lock()
			for f := 0; f < t.model.FactorNum; f++ {
				vGif := gradCoef * vj[f]
				vGifSqr := vGif * vGif
				vSif := invVAlpha * (math.Sqrt(vni[f]+vGifSqr) - math.Sqrt(vni[f]))
				vzi[f] += vGif - vSif*vi[f]
				vni[f] += vGifSqr

				if t.opt.ForceVSparse && vni[f] > 0 && mu.Wi == 0.0 {
					vi[f] = 0.0
				}
			}
			feaLocks[i].Unlock()
		}
	}
}

