"""TSM-X integer decision model. All dimensional API values use SI * 10**6.

No binary floating point, Fraction, numpy or simulator dependency in this package.
Invalid/unrepresentable inputs reject; overflow never silently wraps spatial data.
"""
from .model import *
