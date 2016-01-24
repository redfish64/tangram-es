#include "markers/marker.h"

#include "glm/vec2.hpp"
#include "glm/vec4.hpp"
#include "scene/scene.h"
#include "scene/spriteAtlas.h"

#include <cmath>

namespace Tangram {

Marker::Marker(const Scene& _scene, const std::string& _texture, const std::string& _sprite) {

    // Locate the sprite that this marker will use
    {
        const auto& atlases = _scene.spriteAtlases();
        auto it = atlases.find(_texture);
        if (it != atlases.end()) {
            it->second->getSpriteNode(_sprite, m_sprite);
        }
    }

    // Locate the texture that this marker will use
    {
        const auto& textures = _scene.textures();
        auto it = textures.find(_texture);
        if (it != textures.end()) {
            m_texture = it->second;
        }
    }

}

void Marker::setCoordinates(double _lng, double _lat) {

    m_coordinates = LngLat(_lng, _lat);

}

void Marker::setRotation(float _radians) {

    m_rotation = _radians;

}

}
