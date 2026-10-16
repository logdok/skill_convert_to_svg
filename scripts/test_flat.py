#!/usr/bin/env python3
"""Behavior checks for flat cleanup. Run with ImageMagick and vtracer available."""

import os
import re
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parent


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, **kwargs)


class FlatCleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="flat icon test ")
        self.folder = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_neutral_edges_do_not_turn_blue_and_hidden_rgb_stays_hidden(self):
        # Gray edge is closer to blue than black in naive RGB palette mapping.
        # White is an intentional fill. Hidden red and low alpha are not artwork.
        pixels = bytes([
            100, 100, 100, 255, 255, 255, 255, 255, 78, 157, 196, 255,
            143, 0, 0, 0, 0, 0, 0, 127, 0, 0, 0, 128,
        ])
        source, output = self.folder / "source.png", self.folder / "prepared.png"
        run("magick", "-size", "3x2", "-depth", "8", "rgba:-", str(source), input=pixels)
        run(sys.executable, str(SCRIPTS / "prepare_flat.py"), str(source), str(output),
            "--palette", "#000000,#FFFFFF,#4E9DC4,#8F0000")
        raw = run("magick", str(output), "-depth", "8", "rgba:-").stdout
        self.assertEqual(raw[:12], bytes([0, 0, 0, 255, 255, 255, 255, 255, 78, 157, 196, 255]))
        self.assertEqual(raw[15], 0)
        self.assertEqual(raw[19], 0)
        self.assertEqual(raw[20:24], bytes([0, 0, 0, 255]))

    def test_transparent_hole_survives_full_conversion_and_canvas_fit(self):
        source = self.folder / "shape with space.png"
        run("magick", "-size", "32x48", "xc:none", "-fill", "black",
            "-draw", "rectangle 2,2 29,45", "-fill", "#009245",
            "-draw", "rectangle 6,6 25,41", "-region", "8x8+12+20",
            "-channel", "A", "-evaluate", "set", "0", "+channel", "+region", str(source))
        environment = dict(os.environ)
        environment["PATH"] = str(Path.home() / ".cargo/bin") + os.pathsep + environment.get("PATH", "")
        output = self.folder / "output"
        run("bash", str(SCRIPTS / "convert.sh"), str(source), "--size", "64x64",
            "--keep-background", "--flat-palette", "#000000,#009245",
            "--simplify", "0.8", "--filter-speckle", "1", "-o", str(output), env=environment)
        svg = output / "shape with space.svg"
        root = ET.parse(svg).getroot()
        self.assertEqual(root.attrib["width"], "64")
        self.assertEqual(root.attrib["height"], "64")
        self.assertEqual(root.attrib["viewBox"], "0 0 64 64")
        self.assertFalse(list(root.iter("{http://www.w3.org/2000/svg}image")))
        raw = run("magick", "-background", "none", str(svg), "-depth", "8", "rgba:-").stdout
        self.assertEqual(len(raw), 64 * 64 * 4)
        alpha = lambda x, y: raw[(y * 64 + x) * 4 + 3]
        self.assertEqual(alpha(0, 0), 0)
        self.assertEqual(alpha(32, 32), 0)
        self.assertEqual(alpha(24, 12), 255)
        self.assertFalse((output / ".prep").exists())

    def test_bad_palette_fails_without_creating_output(self):
        output = self.folder / "output.png"
        result = subprocess.run([sys.executable, str(SCRIPTS / "prepare_flat.py"),
            str(self.folder / "missing.png"), str(output), "--palette", "#000000,wrong"], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"invalid palette color", result.stderr)
        self.assertFalse(output.exists())

    def test_larger_canvas_keeps_native_pixels_and_identical_vector_paths(self):
        source = self.folder / "small.png"
        run("magick", "-size", "26x21", "xc:none", "-fill", "black",
            "-draw", "ellipse 13,10 10,8 0,360", "-fill", "#009245",
            "-draw", "ellipse 13,10 7,5 0,360", str(source))
        original_bytes = source.read_bytes()
        environment = dict(os.environ)
        environment["PATH"] = str(Path.home() / ".cargo/bin") + os.pathsep + environment.get("PATH", "")
        for flat in (False, True):
            outputs = []
            for canvas in (None, "512x512"):
                output = self.folder / f"{flat}-{canvas}"
                command = ["bash", str(SCRIPTS / "convert.sh"), str(source),
                    "--keep-background", "--keep-prep", "-o", str(output)]
                command += ["--size", canvas] if canvas else ["--no-resize"]
                if flat:
                    command += ["--flat-palette", "#000000,#009245"]
                run(*command, env=environment)
                outputs.append(ET.parse(output / "small.svg").getroot())
                if flat:
                    size = run("magick", "identify", "-format", "%wx%h",
                        str(output / ".prep/flat_small.png")).stdout
                    self.assertEqual(size, b"26x21")
            native, fitted = outputs
            paths = lambda root: [p.attrib for p in root.iter("{http://www.w3.org/2000/svg}path")]
            self.assertTrue(paths(native))
            self.assertEqual(paths(native), paths(fitted))
            self.assertEqual(fitted.attrib["viewBox"], "0 0 512 512")
            transform = list(fitted)[0].attrib["transform"]
            tx, ty, scale = map(float, re.findall(r"[-+0-9.e]+", transform.replace("translate", "").replace("scale", "")))
            self.assertAlmostEqual(scale, 512 / 26, places=8)
            self.assertAlmostEqual(tx, 0, places=8)
            self.assertAlmostEqual(ty, (512 - 21 * 512 / 26) / 2, places=8)
            self.assertFalse(list(fitted.iter("{http://www.w3.org/2000/svg}image")))
        self.assertEqual(source.read_bytes(), original_bytes)


if __name__ == "__main__":
    unittest.main()
