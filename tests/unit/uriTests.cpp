#include "catch.hpp"

#include "util/uri.h"

using namespace Tangram;

TEST_CASE("Uri parses components correctly", "[Uri]") {

    Uri uri("https://vector.mapzen.com/osm/all/0/0/0.mvt?api_key=mapsRcool#yolo");

    REQUIRE(uri.hasScheme());
    REQUIRE(uri.scheme() == "https");
    REQUIRE(uri.hasHost());
    REQUIRE(uri.host() == "vector.mapzen.com");
    REQUIRE(uri.hasPath());
    REQUIRE(uri.path() == "osm/all/0/0/0.mvt");
    REQUIRE(uri.hasQuery());
    REQUIRE(uri.query() == "api_key=mapsRcool");
    REQUIRE(uri.hasFragment());
    REQUIRE(uri.fragment() == "yolo");

}
