#!/usr/bin/python
# mapnik_pt 2017-02-19 18:30
# reads dirty-tiles file and renders each tile of this list;
# afterwards, deletes the rendered dirty-tiles file;
# call: DTF="dirty_tiles" mapnik_pt.py
# parallel call: DTF="dirty_tiles" PID=123 mapnik_pt.py
# (c) Markus Weber, Nuernberg, License: AGPLv3
from math import pi,cos,sin,log,exp,atan
from subprocess import call
import sys, os
from Queue import Queue
import mapnik
import threading
import shutil

DEG_TO_RAD = pi/180
RAD_TO_DEG = 180/pi

def minmax (a,b,c):
    a = max(a,b)
    a = min(a,c)
    return a

class GoogleProjection:
    def __init__(self,levels=18):
        self.Bc = []
        self.Cc = []
        self.zc = []
        self.Ac = []
        c = 256
        for d in range(0,levels):
            e = c/2;
            self.Bc.append(c/360.0)
            self.Cc.append(c/(2 * pi))
            self.zc.append((e,e))
            self.Ac.append(c)
            c *= 2

    def fromLLtoPixel(self,ll,zoom):
         d = self.zc[zoom]
         e = round(d[0] + ll[0] * self.Bc[zoom])
         f = minmax(sin(DEG_TO_RAD * ll[1]),-0.9999,0.9999)
         g = round(d[1] + 0.5*log((1+f)/(1-f))*-self.Cc[zoom])
         return (e,g)

    def fromPixelToLL(self,px,zoom):
         e = self.zc[zoom]
         f = (px[0] - e[0])/self.Bc[zoom]
         g = (px[1] - e[1])/-self.Cc[zoom]
         h = RAD_TO_DEG * ( 2 * atan(exp(g)) - 0.5 * pi)
         return (f,h)

if __name__ == "__main__":

  # read environment variables
  dt_file_name = os.environ['DTF']
  try:
    temp_file = "/dev/shm/tile" + os.environ['PID']
  except:
    temp_file = "/dev/shm/tile"

  # do some global initialization
  print "Rendering " + dt_file_name + ": started."
  mapfile = "/oprm2/toolchain/mapnik_oprm.xml"
  tile_dir = "/oprm2/tiles/"
  max_zoom = 8
  tile_count = 0
  empty_tile_count = 0

  # create tile directory and all possible zoom directories
  if not os.path.isdir(tile_dir):
    os.mkdir(tile_dir)
  for z in range(0, max_zoom):
    d = tile_dir + "%s" % z + "/"
    if not os.path.isdir(d):
      os.mkdir(d)

  # open the dirty-tiles file
  try:
    dt_file = file(dt_file_name, "r")
  except:
    dt_file = None
  if (dt_file != None):

    # do some Mapnik initialization
    mm = mapnik.Map(256, 256)
    mapnik.load_map(mm, mapfile, True)
    # Obtain <Map> projection
    prj = mapnik.Projection(mm.srs)
    # Projects between tile pixel co-ordinates and LatLong (EPSG:4326)
    tileproj = GoogleProjection(max_zoom + 1)

    # process the dirty-tiles file
    while True:

      # read a line of the dirty-tiles file
      line = dt_file.readline()
      if (line == ""):
        break
      line_part = line.strip().split('/')

      # create x coordinate's directory - if necessary
      d = tile_dir + line_part[0] + "/" + line_part[1] + "/"
      if not os.path.isdir(d):
        os.mkdir(d)

      # get parameters of the line
      z = int(line_part[0])
      x = int(line_part[1])
      y = int(line_part[2])
      tile_name= tile_dir + line[:-1] + ".png"

      # render this tile -- start

      # Calculate pixel positions of bottom-left & top-right
      p0 = (x * 256, (y + 1) * 256)
      p1 = ((x + 1) * 256, y * 256)

      # Convert to LatLong (EPSG:4326)
      l0 = tileproj.fromPixelToLL(p0, z);
      l1 = tileproj.fromPixelToLL(p1, z);

      # Convert to map projection (e.g. mercator co-ords EPSG:900913)
      c0 = prj.forward(mapnik.Coord(l0[0], l0[1]))
      c1 = prj.forward(mapnik.Coord(l1[0], l1[1]))

      # Bounding box for the tile
      if hasattr(mapnik,'mapnik_version') and mapnik.mapnik_version() >= 800:
        bbox = mapnik.Box2d(c0.x,c0.y, c1.x,c1.y)
      else:
      	bbox = mapnik.Envelope(c0.x,c0.y, c1.x,c1.y)
      render_size = 256
      mm.resize(render_size, render_size)
      mm.zoom_to_box(bbox)
      mm.buffer_size = 256  # (buffer size was 128)

      # render image with default Agg renderer
      im = mapnik.Image(render_size, render_size)
      mapnik.render(mm, im)
      im.save(temp_file, 'png256')
      tile_count = tile_count + 1

      # render this tile -- end

      # copy this tile to tile tree
      l= os.stat(temp_file)[6]
      if l>116:
        shutil.copyfile(temp_file,tile_name)
      else:
        try:
          os.unlink(tile_name)
        except:
          l= l  # (file did not exist)
        empty_tile_count = empty_tile_count + 1

    # close and delete the dirty-tiles file
    dt_file.close()
    try:
      os.unlink(dt_file_name)
    except:
      l= l  # (file did not exist)

  # print some statistics
  print "Rendering " + dt_file_name + ":", tile_count, "tiles (" + "%s" % empty_tile_count + " empty)."
