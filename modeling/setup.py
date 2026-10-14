"""
Setup configuration for SautiFlow DSP Modeling library.
"""

from setuptools import setup, find_packages

setup(
    name="dsp_modeling",
    version="1.0.0",
    description="Mathematical DSP modeling library for SautiFlow / MiniAudioDart audio engine",
    author="SautiFlow Engineering & Mathematical Audio Contributors",
    packages=find_packages(),
    python_requires=">=3.9",
    install_requires=[
        "numpy>=1.24.0",
        "scipy>=1.10.0",
        "matplotlib>=3.7.0",
    ],
    extras_require={
        "dev": [
            "jupyter>=1.0.0",
            "nbformat>=5.9.0",
            "pytest>=7.0.0",
        ]
    },
    classifiers=[
        "Topic :: Multimedia :: Sound/Audio :: Analysis",
        "Topic :: Scientific/Engineering :: Mathematics",
        "Programming Language :: Python :: 3",
        "Operating System :: OS Independent",
    ],
)
