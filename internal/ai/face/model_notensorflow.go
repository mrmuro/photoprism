//go:build notensorflow

package face

import (
	"errors"
	"image"

	"github.com/photoprism/photoprism/internal/ai/tensorflow"
)

// ErrTensorFlowUnavailable is returned when a TensorFlow face model is requested from a
// binary built with the notensorflow tag. The ONNX embedding models are unaffected.
var ErrTensorFlowUnavailable = errors.New("faces: TensorFlow models are not supported by this build, select an ONNX model with PHOTOPRISM_FACE_MODEL")

// Model stands in for the TensorFlow FaceNet model in builds without TensorFlow.
type Model struct {
	name       ModelName
	resolution int
	dims       int
	disabled   bool
}

// NewModel returns a placeholder that never loads, so callers fall back to the ONNX models.
func NewModel(name ModelName, modelPath, cachePath string, resolution int, meta *tensorflow.ModelInfo, disabled bool) *Model {
	if name == "" {
		name = ModelFaceNet
	}

	if resolution == 0 {
		resolution = CropSize.Width
	}

	if meta == nil {
		meta = new(tensorflow.ModelInfo)
	}

	return &Model{
		name:       name,
		resolution: resolution,
		dims:       modelDims(name, meta),
		disabled:   disabled,
	}
}

// modelDims returns the embedding length of a TensorFlow model.
func modelDims(name ModelName, meta *tensorflow.ModelInfo) int {
	if meta.Output != nil && meta.Output.NumOutputs > 0 {
		return int(meta.Output.NumOutputs)
	}

	if info := FindEmbeddingModel(name); info != nil {
		return info.Dims
	}

	return len(NullEmbedding)
}

// ModelName returns the name of the embedding model.
func (m *Model) ModelName() ModelName {
	return m.name
}

// Dims returns the length of the embeddings the model produces.
func (m *Model) Dims() int {
	return m.dims
}

// CropSize returns the input width and height the model expects.
func (m *Model) CropSize() (width, height int) {
	return m.resolution, m.resolution
}

// Aligned reports whether the model requires landmark-aligned crops.
func (m *Model) Aligned() bool {
	return false
}

// Close is a no-op because nothing is ever loaded.
func (m *Model) Close() error {
	return nil
}

// Detect runs face detection only; embeddings require TensorFlow.
func (m *Model) Detect(fileName string, minSize int, cacheCrop bool, expected int) (faces Faces, err error) {
	faces, err = Detect(fileName, minSize)

	if err != nil || m.disabled {
		return faces, err
	} else if c := len(faces); c == 0 || expected > 0 && c == expected {
		return faces, nil
	}

	return faces, ErrTensorFlowUnavailable
}

// Init fails unless the model is disabled, since TensorFlow is not available.
func (m *Model) Init() error {
	if m.disabled {
		return nil
	}

	return ErrTensorFlowUnavailable
}

// ModelLoaded always returns false in builds without TensorFlow.
func (m *Model) ModelLoaded() bool {
	return false
}

// Run returns no embeddings in builds without TensorFlow.
func (m *Model) Run(img image.Image) Embeddings {
	return nil
}
