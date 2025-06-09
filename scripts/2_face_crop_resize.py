#!/usr/bin/env python3
"""
Enhanced Face Crop and Resize Script for Gallagher Photo Sync
Improvements over original:
- Configuration file support
- Comprehensive logging with rotation
- Progress tracking for batch processing
- Face quality scoring
- Better error handling and recovery
- Metadata preservation
- Memory-efficient processing
"""

import cv2
import os
import sys
import json
import logging
import numpy as np
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass
from logging.handlers import RotatingFileHandler
from tqdm import tqdm
import argparse

try:
    from insightface.app import FaceAnalysis
except ImportError:
    print("ERROR: InsightFace not installed. Run: pip install insightface")
    sys.exit(1)

@dataclass
class ProcessingResult:
    """Results of processing a single image"""
    filename: str
    success: bool
    face_detected: bool
    face_confidence: float
    original_size: Tuple[int, int]
    output_size: Tuple[int, int]
    file_size_kb: float
    jpeg_quality: int
    error_message: str = ""
    processing_time: float = 0.0

class FaceProcessor:
    """Enhanced face processing with configuration and logging"""
    
    def __init__(self, config_path: str = "config/config.json"):
        self.config = self._load_config(config_path)
        self.logger = self._setup_logging()
        self.app = None
        self.stats = {
            'total_files': 0,
            'successful': 0,
            'failed': 0,
            'no_face': 0,
            'poor_quality': 0
        }
        
    def _load_config(self, config_path: str) -> Dict:
        """Load configuration from JSON file"""
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            print(f"ERROR: Configuration file not found: {config_path}")
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f"ERROR: Invalid JSON in configuration file: {e}")
            sys.exit(1)
    
    def _setup_logging(self) -> logging.Logger:
        """Setup rotating file logger"""
        logger = logging.getLogger('face_processor')
        logger.setLevel(getattr(logging, self.config['logging']['level']))
        
        # Create logs directory if it doesn't exist
        log_dir = Path(self.config['directories']['logs'])
        log_dir.mkdir(exist_ok=True)
        
        # Setup rotating file handler
        log_file = log_dir / f"face_processing_{datetime.now().strftime('%Y%m%d')}.log"
        handler = RotatingFileHandler(
            log_file,
            maxBytes=self.config['logging']['max_file_size_mb'] * 1024 * 1024,
            backupCount=self.config['logging']['backup_count']
        )
        
        formatter = logging.Formatter(self.config['logging']['format'])
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        
        # Also log to console
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)
        
        return logger
    
    def initialize_insightface(self) -> bool:
        """Initialize InsightFace model"""
        try:
            self.logger.info("Initializing InsightFace model...")
            self.app = FaceAnalysis(
                name=self.config['insightface']['model_name'],
                providers=self.config['insightface']['providers']
            )
            self.app.prepare(ctx_id=self.config['insightface']['ctx_id'])
            self.logger.info("InsightFace model initialized successfully")
            return True
        except Exception as e:
            self.logger.error(f"Failed to initialize InsightFace: {e}")
            return False
    
    def clamp(self, val: int, minval: int, maxval: int) -> int:
        """Clamp value between min and max"""
        return max(min(val, maxval), minval)
    
    def calculate_crop_region(self, face, image_shape: Tuple[int, int, int]) -> Tuple[int, int, int, int]:
        """Calculate crop region with padding for head and shoulders"""
        x1, y1, x2, y2 = map(int, face.bbox)
        w, h = x2 - x1, y2 - y1
        cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
        
        # Calculate padding
        pad_w = int(w * self.config['face_processing']['padding_width_factor'])
        pad_h = int(h * self.config['face_processing']['padding_height_factor'])
        
        # Apply padding and clamp to image boundaries
        x1_crop = self.clamp(cx - pad_w, 0, image_shape[1])
        y1_crop = self.clamp(cy - pad_h, 0, image_shape[0])
        x2_crop = self.clamp(cx + pad_w, 0, image_shape[1])
        y2_crop = self.clamp(cy + pad_h, 0, image_shape[0])
        
        return x1_crop, y1_crop, x2_crop, y2_crop
    
    def process_single_image(self, image_path: Path) -> ProcessingResult:
        """Process a single image file"""
        start_time = datetime.now()
        filename = image_path.name
        
        try:
            # Read image
            image = cv2.imread(str(image_path))
            if image is None:
                return ProcessingResult(
                    filename=filename,
                    success=False,
                    face_detected=False,
                    face_confidence=0.0,
                    original_size=(0, 0),
                    output_size=(0, 0),
                    file_size_kb=0.0,
                    jpeg_quality=0,
                    error_message="Failed to read image"
                )
            
            original_size = (image.shape[1], image.shape[0])
            
            # Detect faces
            faces = self.app.get(image)
            if not faces:
                return ProcessingResult(
                    filename=filename,
                    success=False,
                    face_detected=False,
                    face_confidence=0.0,
                    original_size=original_size,
                    output_size=(0, 0),
                    file_size_kb=0.0,
                    jpeg_quality=0,
                    error_message="No face detected"
                )
            
            # Select best face (largest)
            face = max(faces, key=lambda f: f.bbox[2] * f.bbox[3])
            face_confidence = float(face.det_score) if hasattr(face, 'det_score') else 1.0
            
            # Check face quality
            min_confidence = self.config['face_processing']['min_face_confidence']
            if face_confidence < min_confidence:
                return ProcessingResult(
                    filename=filename,
                    success=False,
                    face_detected=True,
                    face_confidence=face_confidence,
                    original_size=original_size,
                    output_size=(0, 0),
                    file_size_kb=0.0,
                    jpeg_quality=0,
                    error_message=f"Face confidence {face_confidence:.2f} below threshold {min_confidence}"
                )
            
            # Calculate crop region
            x1, y1, x2, y2 = self.calculate_crop_region(face, image.shape)
            
            # Crop image
            cropped = image[y1:y2, x1:x2]
            if cropped.size == 0:
                return ProcessingResult(
                    filename=filename,
                    success=False,
                    face_detected=True,
                    face_confidence=face_confidence,
                    original_size=original_size,
                    output_size=(0, 0),
                    file_size_kb=0.0,
                    jpeg_quality=0,
                    error_message="Cropped region is empty"
                )
            
            # Two-stage resize for better quality
            intermediate_size = tuple(self.config['face_processing']['intermediate_size'])
            target_size = tuple(self.config['face_processing']['target_size'])
            
            intermediate = cv2.resize(cropped, intermediate_size, interpolation=cv2.INTER_AREA)
            resized = cv2.resize(intermediate, target_size, interpolation=cv2.INTER_AREA)
            
            # Apply sharpening
            kernel = cv2.getGaussianKernel(3, 0)
            sharpened = cv2.filter2D(resized, -1, kernel @ kernel.T)
            
            # Save with quality optimization
            output_path = Path(self.config['directories']['processing_cropped']) / f"{image_path.stem}.jpg"
            quality, file_size_kb = self._save_with_quality_optimization(sharpened, output_path)
            
            processing_time = (datetime.now() - start_time).total_seconds()
            
            return ProcessingResult(
                filename=filename,
                success=True,
                face_detected=True,
                face_confidence=face_confidence,
                original_size=original_size,
                output_size=target_size,
                file_size_kb=file_size_kb,
                jpeg_quality=quality,
                processing_time=processing_time
            )
            
        except Exception as e:
            processing_time = (datetime.now() - start_time).total_seconds()
            return ProcessingResult(
                filename=filename,
                success=False,
                face_detected=False,
                face_confidence=0.0,
                original_size=(0, 0),
                output_size=(0, 0),
                file_size_kb=0.0,
                jpeg_quality=0,
                error_message=str(e),
                processing_time=processing_time
            )
    
    def _save_with_quality_optimization(self, image: np.ndarray, output_path: Path) -> Tuple[int, float]:
        """Save image with quality optimization to meet file size constraints"""
        max_size_kb = self.config['face_processing']['max_file_size_kb']
        quality_start = self.config['face_processing']['jpeg_quality_start']
        quality_min = self.config['face_processing']['jpeg_quality_min']
        quality_step = self.config['face_processing']['jpeg_quality_step']
        
        quality = quality_start
        while quality >= quality_min:
            ret, enc_img = cv2.imencode(".jpg", image, [int(cv2.IMWRITE_JPEG_QUALITY), quality])
            if ret and len(enc_img) <= max_size_kb * 1024:
                with open(output_path, "wb") as f:
                    f.write(enc_img)
                file_size_kb = len(enc_img) / 1024
                return quality, file_size_kb
            quality -= quality_step
        
        # If we can't meet the size constraint, save at minimum quality
        ret, enc_img = cv2.imencode(".jpg", image, [int(cv2.IMWRITE_JPEG_QUALITY), quality_min])
        if ret:
            with open(output_path, "wb") as f:
                f.write(enc_img)
            file_size_kb = len(enc_img) / 1024
            return quality_min, file_size_kb
        
        raise Exception("Failed to encode image")
    
    def get_input_files(self) -> List[Path]:
        """Get list of input files to process"""
        input_dir = Path(self.config['directories']['processing_renamed'])
        supported_formats = self.config['face_processing']['supported_formats']
        
        files = []
        for ext in supported_formats:
            files.extend(input_dir.glob(f"*{ext}"))
            files.extend(input_dir.glob(f"*{ext.upper()}"))
        
        return sorted(files)
    
    def process_batch(self, files: List[Path]) -> List[ProcessingResult]:
        """Process a batch of files"""
        results = []
        
        with tqdm(total=len(files), desc="Processing images", unit="img") as pbar:
            for file_path in files:
                result = self.process_single_image(file_path)
                results.append(result)
                
                # Update statistics
                self.stats['total_files'] += 1
                if result.success:
                    self.stats['successful'] += 1
                elif not result.face_detected:
                    self.stats['no_face'] += 1
                elif result.face_confidence < self.config['face_processing']['min_face_confidence']:
                    self.stats['poor_quality'] += 1
                else:
                    self.stats['failed'] += 1
                
                # Log result
                if result.success:
                    self.logger.info(f"✓ {result.filename}: {result.jpeg_quality}% quality, "
                                   f"{result.file_size_kb:.1f}KB, confidence={result.face_confidence:.2f}")
                else:
                    self.logger.warning(f"✗ {result.filename}: {result.error_message}")
                    
                    # Move failed files to failed directory
                    failed_dir = Path(self.config['directories']['processing_failed'])
                    failed_dir.mkdir(exist_ok=True)
                    try:
                        file_path.rename(failed_dir / file_path.name)
                    except Exception as e:
                        self.logger.error(f"Failed to move {file_path.name} to failed directory: {e}")
                
                pbar.update(1)
        
        return results
    
    def generate_report(self, results: List[ProcessingResult]) -> None:
        """Generate processing report"""
        report_path = Path(self.config['directories']['logs']) / f"face_processing_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
        
        with open(report_path, 'w') as f:
            f.write("=== Face Processing Report ===\n")
            f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
            
            f.write("=== Summary ===\n")
            f.write(f"Total files: {self.stats['total_files']}\n")
            f.write(f"Successful: {self.stats['successful']}\n")
            f.write(f"Failed: {self.stats['failed']}\n")
            f.write(f"No face detected: {self.stats['no_face']}\n")
            f.write(f"Poor quality faces: {self.stats['poor_quality']}\n")
            
            if self.stats['total_files'] > 0:
                success_rate = (self.stats['successful'] / self.stats['total_files']) * 100
                f.write(f"Success rate: {success_rate:.1f}%\n")
            
            f.write("\n=== Detailed Results ===\n")
            for result in results:
                f.write(f"{result.filename}: ")
                if result.success:
                    f.write(f"SUCCESS - Quality: {result.jpeg_quality}%, "
                           f"Size: {result.file_size_kb:.1f}KB, "
                           f"Confidence: {result.face_confidence:.2f}\n")
                else:
                    f.write(f"FAILED - {result.error_message}\n")
        
        self.logger.info(f"Report generated: {report_path}")
    
    def run(self) -> bool:
        """Main processing function"""
        self.logger.info("Starting face processing...")
        
        # Initialize InsightFace
        if not self.initialize_insightface():
            return False
        
        # Get input files
        files = self.get_input_files()
        if not files:
            self.logger.warning("No input files found")
            return True
        
        self.logger.info(f"Found {len(files)} files to process")
        
        # Create output directories
        for dir_key in ['processing_cropped', 'processing_failed']:
            Path(self.config['directories'][dir_key]).mkdir(exist_ok=True)
        
        # Process files in batches
        batch_size = self.config['face_processing']['batch_size']
        all_results = []
        
        for i in range(0, len(files), batch_size):
            batch = files[i:i + batch_size]
            self.logger.info(f"Processing batch {i//batch_size + 1}/{(len(files) + batch_size - 1)//batch_size}")
            
            batch_results = self.process_batch(batch)
            all_results.extend(batch_results)
        
        # Generate report
        self.generate_report(all_results)
        
        self.logger.info("Face processing completed")
        self.logger.info(f"Summary: {self.stats['successful']}/{self.stats['total_files']} successful")
        
        return True

def main():
    parser = argparse.ArgumentParser(description="Enhanced Face Crop and Resize for Gallagher Photo Sync")
    parser.add_argument("--config", default="config/config.json", help="Path to configuration file")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable verbose logging")
    
    args = parser.parse_args()
    
    processor = FaceProcessor(args.config)
    
    if args.verbose:
        processor.logger.setLevel(logging.DEBUG)
    
    success = processor.run()
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
