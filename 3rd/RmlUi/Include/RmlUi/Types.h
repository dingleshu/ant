/*
 * This source file is part of RmlUi, the HTML/CSS Interface Middleware
 *
 * For the latest information, see http://github.com/mikke89/RmlUi
 *
 * Copyright (c) 2008-2010 CodePoint Ltd, Shift Technology Ltd
 * Copyright (c) 2019 The RmlUi Team, and contributors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */

#ifndef RMLUI_CORE_TYPES_H
#define RMLUI_CORE_TYPES_H

#include <utility>
#include <vector>
#include <string>
#include <stack>
#include <list>
#include <functional>
#include <queue>
#include <array>
#include <unordered_map>
#include <memory>
#include <set>
#include <unordered_set>
#include <variant>
#include <cstdlib>
#include "Traits.h"
#include "Colour.h"
#include "ObserverPtr.h"
#include "Variant.h"

namespace Rml {

// Common classes
class Document;
class Element;
class ElementText;
class ElementAnimation;
class Event;
class Property;
class Transform;
class PropertyIdSet;
struct Animation;
struct Transition;
struct TransitionList;
enum class EventId : uint16_t;
enum class PropertyId : uint8_t;

// Types for external interfaces.
using FileHandle = uintptr_t;
using FontFaceHandle = uintptr_t;
using TextEffectsHandle = uintptr_t;

using DocumentPtr = std::unique_ptr<Document>;
using ElementPtr = std::unique_ptr<Element>;
using TextPtr = ElementPtr;// std::unique_ptr<ElementText>;

// Container types for common classes
using ElementList = std::vector< Element* >;
using OwnedElementList = std::vector< ElementPtr >;
using VariantList = std::vector< Variant >;
using ElementAnimationList = std::vector< ElementAnimation >;

using AttributeNameList = std::unordered_set< std::string >;
using PropertyMap = std::unordered_map< PropertyId, Property >;

using EventDictionary = std::unordered_map< std::string, EventVariant >;
using ElementAttributes = std::unordered_map< std::string, std::string >;

using AnimationList = std::vector<Animation>;

// Additional smart pointers
using TransformPtr = std::shared_ptr< Transform >;

// Data binding types
class DataView;
using DataViewPtr = std::unique_ptr<DataView, Releaser<DataView>>;
class DataController;
using DataControllerPtr = std::unique_ptr<DataController, Releaser<DataController>>;

enum class Character : char32_t { Null, Replacement = 0xfffd };

typedef uint8_t PseudoClassSet;

enum class PseudoClass : uint8_t {
	Hover  = 0x01,
	Active = 0x02,
};

inline PseudoClassSet operator| (PseudoClass a, PseudoClass b) { return (uint8_t)a | (uint8_t)b; }
inline PseudoClassSet operator| (PseudoClassSet a, PseudoClass b) { return a | (uint8_t)b; }
inline PseudoClassSet operator~ (PseudoClass a) { return ~(uint8_t)a; }
inline PseudoClassSet operator& (PseudoClassSet a, PseudoClass b) { return a & (uint8_t)b; }

struct Point {
	float x{};
	float y{};
	Point() {}
	Point(float x_, float y_) : x(x_), y(y_) {}
	void SetPoint(float x_, float y_) {
		x = x_;
		y = y_;
	}
};

struct Size {
	float w{};
	float h{};
	Size() {}
	Size(float width, float height) : w(width), h(height) {}
	bool IsEmpty() const { return !w || !h; }
	void SetSize(float width, float height) {
		w = width;
		h = height;
	}
};

struct Quad {
	Point a, b, c, d;
};

template <typename T>
struct EdgeInsets {
	T left{};
	T top{};
	T right{};
	T bottom{};
	T& operator[](size_t i) const {
		return ((T*)this)[i];
	}
	bool operator==(const EdgeInsets& rhs) const {
		return std::tie(left, top, right, bottom) == std::tie(rhs.left, rhs.top, rhs.right, bottom);
	}
	bool operator!=(const EdgeInsets& rhs) const {
		return !(*this == rhs);
	}
};

template <typename T>
struct CornerInsets {
	T topLeft{};
	T topRight{};
	T bottomRight{};
	T bottomLeft{};
	T& operator[](size_t i) const {
		return ((T*)this)[i];
	}
	bool operator==(const CornerInsets& rhs) const {
		return std::tie(topLeft, topRight, bottomLeft, bottomRight) == std::tie(rhs.topLeft, rhs.topRight, rhs.bottomLeft, bottomRight);
	}
	bool operator!=(const CornerInsets& rhs) const {
		return !(*this == rhs);
	}
};

struct Rect {
	Point origin;
	Size size;
	Rect() : origin(), size() {}
	Rect(float x, float y, float width, float height) : origin(x, y), size(width, height) {}
	Rect(const Point& origin_, const Size& size_) : origin(origin_), size(size_) {}
	float x() const { return origin.x; }
	float y() const { return origin.y; }
	float width() const { return size.w; }
	float height() const { return size.h; }
	float left() const { return origin.x; }
	float top() const { return origin.y; }
	float right() const { return left() + width(); }
	float bottom() const { return top() + height(); }
	bool IsEmpty() const { return size.IsEmpty(); }
	void SetRect(float x, float y, float width, float height) {
		origin.SetPoint(x, y);
		size.SetSize(width, height);
	}
	void Union(const Rect& rect) {
		float rx = std::min(x(), rect.x());
		float ry = std::min(y(), rect.y());
		float rr = std::max(right(), rect.right());
		float rb = std::max(bottom(), rect.bottom());
		SetRect(rx, ry, rr - rx, rb - ry);
	}
	bool Contains(const Point& point) const {
		return (point.x >= x()) && (point.x < right()) && (point.y >= y()) && (point.y < bottom());
	}
	CornerInsets<Point> Vertex() const {
		return {
			{left(), top()},
			{right(), top()},
			{right(), bottom()},
			{left(), bottom()}
		};
	}
};

inline bool operator==(const Point& lhs, const Point& rhs) {
	return lhs.x == rhs.x && lhs.y == rhs.y;
}
inline bool operator!=(const Point& lhs, const Point& rhs) {
	return !(lhs == rhs);
}
inline bool operator==(const Size& lhs, const Size& rhs) {
	return lhs.w == rhs.w && lhs.h == rhs.h;
}
inline bool operator!=(const Size& lhs, const Size& rhs) {
	return !(lhs == rhs);
}
inline bool operator==(const Rect& lhs, const Rect& rhs) {
	return lhs.origin == rhs.origin && lhs.size == rhs.size;
}
inline bool operator!=(const Rect& lhs, const Rect& rhs) {
	return !(lhs == rhs);
}

inline Point operator+(const Point& lhs, const Point& rhs) {
	return Point(lhs.x + rhs.x, lhs.y + rhs.y);
}
inline Point operator-(const Point& lhs, const Point& rhs) {
	return Point(lhs.x - rhs.x, lhs.y - rhs.y);
}
inline Point operator+(const Point& lhs, const Size& rhs) {
	return Point(lhs.x + rhs.w, lhs.y + rhs.h);
}
inline Point operator-(const Point& lhs, const Size& rhs) {
	return Point(lhs.x - rhs.w, lhs.y - rhs.h);
}
inline Size operator+(const Size& lhs, const Size& rhs) {
	return Size(lhs.w + rhs.w, lhs.h + rhs.h);
}
inline Size operator-(const Size& lhs, const Size& rhs) {
	return Size(lhs.w - rhs.w, lhs.h - rhs.h);
}

inline EdgeInsets<float> operator+(const EdgeInsets<float>& lhs, const EdgeInsets<float>& rhs) {
	return EdgeInsets<float> {
		lhs.left + rhs.left,
		lhs.top + rhs.top,
		lhs.right + rhs.right,
		lhs.bottom + rhs.bottom,
	};
}

inline Point operator+(const Point& lhs, const EdgeInsets<float>& rhs) {
	return Point(lhs.x + rhs.left, lhs.y + rhs.top);
}
inline Point operator-(const Point& lhs, const EdgeInsets<float>& rhs) {
	return Point(lhs.x - rhs.left, lhs.y - rhs.top);
}
inline Size operator+(const Size& lhs, const EdgeInsets<float>& rhs) {
	return Size(lhs.w + rhs.left + rhs.right, lhs.h + rhs.top + rhs.bottom);
}
inline Size operator-(const Size& lhs, const EdgeInsets<float>& rhs) {
	return Size(lhs.w - rhs.left - rhs.right, lhs.h - rhs.top - rhs.bottom);
}
inline Rect operator+(const Rect& lhs, const EdgeInsets<float>& rhs) {
	return Rect(lhs.origin - rhs, lhs.size + rhs);
}
inline Rect operator-(const Rect& lhs, const EdgeInsets<float>& rhs) {
	return Rect(lhs.origin + rhs, lhs.size - rhs);
}

inline Point operator*(const Point& lhs, const Point& rhs) {
	return Point(lhs.x * rhs.x, lhs.y * rhs.y);
}
inline Size operator*(const Size& lhs, float rhs) {
	return Size(lhs.w * rhs, lhs.h * rhs);
}
} // namespace Rml


namespace std {
// Hash specialization for enum class types (required on some older compilers)
template <> struct hash<::Rml::PropertyId> {
	using utype = typename ::std::underlying_type<::Rml::PropertyId>::type;
	size_t operator() (const ::Rml::PropertyId& t) const { std::hash<utype> h; return h(static_cast<utype>(t)); }
};
template <> struct hash<::Rml::Character> {
	using utype = typename ::std::underlying_type<::Rml::Character>::type;
	size_t operator() (const ::Rml::Character& t) const { std::hash<utype> h; return h(static_cast<utype>(t)); }
};
}

#endif
