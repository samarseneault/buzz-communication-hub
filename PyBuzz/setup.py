from setuptools import setup, Extension
from Cython.Distutils import build_ext

NAME = "pybuzz"
VERSION = "0.1"
DESCR = "Python Wrapper for Buzz Virtual Machine"
REQUIRES = ['cython']

AUTHOR = "Ryan Cotsakis"
EMAIL = "ryan.cotsakis@polymtl.ca"
SRC_DIR = "pybuzz"
PACKAGES = [SRC_DIR]

ext_1 = Extension(NAME,
                  [SRC_DIR + "/buzz_utility.c", SRC_DIR + "/pybuzz.pyx"],
                  libraries=['buzz', 'buzzdbg'])

EXTENSIONS = [ext_1]


if __name__ == "__main__":
    setup(install_requires=REQUIRES,
          packages=PACKAGES,
          zip_safe=False,
          name=NAME,
          version=VERSION,
          description=DESCR,
          author=AUTHOR,
          author_email=EMAIL,
          cmdclass={"build_ext": build_ext},
          ext_modules=EXTENSIONS
          )
