from __future__ import annotations

import gc
import unittest

import numpy as np

from linux.task3_pipeline import ModelInput, ModelInputSpec, PreprocessTransform
from linux.task3_pipeline.models import FrameMetadata


class ModelInputContractTests(unittest.TestCase):
    def test_yolov5_baseline_is_explicit_and_size_is_configurable(self) -> None:
        baseline = ModelInputSpec(width=640, height=640)

        self.assertEqual(baseline.batch_size, 1)
        self.assertEqual(baseline.shape, (1, 640, 640, 3))
        self.assertEqual(baseline.layout, "NHWC")
        self.assertEqual(baseline.dtype, np.dtype("uint8"))
        self.assertEqual(baseline.color_format, "RGB")
        self.assertEqual(baseline.padding_value, 0)

        alternate = ModelInputSpec(width=320, height=512, padding_value=114)
        self.assertEqual(alternate.shape, (1, 512, 320, 3))
        self.assertEqual(alternate.padding_value, 114)

    def test_transform_records_source_target_scale_and_each_padding_side(self) -> None:
        transform = PreprocessTransform(
            source_width=1280,
            source_height=720,
            model_width=640,
            model_height=640,
            scale=0.5,
            pad_left=0,
            pad_top=140,
            pad_right=0,
            pad_bottom=140,
        )

        self.assertEqual(transform.source_width, 1280)
        self.assertEqual(transform.source_height, 720)
        self.assertEqual(transform.model_width, 640)
        self.assertEqual(transform.model_height, 640)
        self.assertEqual(transform.ratio, 0.5)
        self.assertEqual(
            (transform.pad_left, transform.pad_right, transform.pad_top, transform.pad_bottom),
            (0, 0, 140, 140),
        )

    def test_input_owns_contiguous_read_only_tensor_for_its_lifetime(self) -> None:
        spec = ModelInputSpec(width=640, height=640)
        source = np.zeros((1, 640, 1280, 3), dtype=np.uint8)[:, :, :640, :]
        self.assertFalse(source.flags.c_contiguous)
        result = ModelInput(
            self._metadata(), source, spec, self._transform_for(spec)
        )

        source[:, :, :, :] = 99
        del source
        gc.collect()

        self.assertEqual(result.data[0, 0, 0, 0], 0)
        self.assertTrue(result.data.flags.c_contiguous)
        self.assertTrue(result.data.flags.owndata)
        self.assertFalse(result.data.flags.writeable)
        with self.assertRaises(ValueError):
            result.data[0, 0, 0, 0] = 1

    def test_input_preserves_complete_metadata_object(self) -> None:
        metadata = self._metadata()
        spec = ModelInputSpec(width=640, height=640)
        result = ModelInput(
            metadata,
            np.zeros(spec.shape, dtype=np.uint8),
            spec,
            self._transform_for(spec),
        )

        self.assertIs(result.metadata, metadata)
        self.assertEqual(result.metadata.source_name, "decoded-camera")
        self.assertEqual(result.metadata.received_monotonic_ns, 101)
        self.assertEqual(result.metadata.source_timestamp, 202)
        self.assertEqual(result.metadata.timestamp_domain, "sensor_clock")
        self.assertEqual(result.metadata.wire_sequence, 303)

    def test_input_rejects_wrong_shape_dtype_or_target(self) -> None:
        spec = ModelInputSpec(width=640, height=640)
        with self.assertRaises(ValueError):
            ModelInput(
                self._metadata(),
                np.zeros((640, 640, 3), dtype=np.uint8),
                spec,
                self._transform_for(spec),
            )
        with self.assertRaises(ValueError):
            ModelInput(
                self._metadata(),
                np.zeros(spec.shape, dtype=np.float32),
                spec,
                self._transform_for(spec),
            )
        with self.assertRaises(ValueError):
            ModelInput(
                self._metadata(),
                np.zeros(spec.shape, dtype=np.uint8),
                spec,
                PreprocessTransform(1280, 720, 320, 640, 0.5, 0, 140, 0, 140),
            )

    @staticmethod
    def _transform_for(spec: ModelInputSpec) -> PreprocessTransform:
        return PreprocessTransform(1280, 720, spec.width, spec.height, 0.5, 0, 140, 0, 140)

    @staticmethod
    def _metadata() -> FrameMetadata:
        return FrameMetadata(
            ingest_id=7,
            source_name="decoded-camera",
            payload_length=3,
            received_monotonic_ns=101,
            frame_id="frame-7",
            wire_sequence=303,
            source_timestamp=202,
            timestamp_domain="sensor_clock",
            transport="mock",
            encoding="jpeg",
            declared_width=1280,
            declared_height=720,
            integrity={"crc": "verified"},
            protocol_version=1,
            extensions={"origin": "contract-test"},
        )
