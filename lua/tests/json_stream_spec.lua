local stream = require('model.util.json_stream_ds')

describe('json_stream', function()
  describe('object parsing', function()
    it('should parse a simple object', function()
      local my_name_object = {}

      local handle_name_object_partial = stream.object(function()
        return {
          name = function()
            local _name = ''

            return function(part, is_complete)
              _name = _name .. part

              if is_complete then
                my_name_object.name = _name
              end
            end
          end,
        }
      end)()

      handle_name_object_partial('{"na')
      handle_name_object_partial('me')
      handle_name_object_partial('":')
      handle_name_object_partial('"b')
      handle_name_object_partial('ob')
      handle_name_object_partial('"}', true)

      assert.are.equal('bob', my_name_object.name)
    end)
  end)

  describe('list parsing', function()
    it('should parse a list of objects', function()
      local my_name_object_list = {}

      local handle_list_of_name_object_partials = stream.list(function()
        return {
          name = function()
            local _name = ''

            return function(part, is_complete)
              _name = _name .. part

              if is_complete then
                table.insert(my_name_object_list, {
                  name = _name,
                })
              end
            end
          end,
        }
      end)()

      handle_list_of_name_object_partials('[')
      handle_list_of_name_object_partials('{"na')
      handle_list_of_name_object_partials('me')
      handle_list_of_name_object_partials('":')
      handle_list_of_name_object_partials('"ma')
      handle_list_of_name_object_partials('ry')
      handle_list_of_name_object_partials('"},')

      assert.are.equal(1, #my_name_object_list)

      handle_list_of_name_object_partials('{"na')
      handle_list_of_name_object_partials('me')
      handle_list_of_name_object_partials('":')
      handle_list_of_name_object_partials('"s')
      handle_list_of_name_object_partials('ue')
      handle_list_of_name_object_partials('"}')
      handle_list_of_name_object_partials(']', true)

      assert.are.equal(2, #my_name_object_list)
    end)
  end)

  describe('nested parsing', function()
    it('should parse an object with a nested list', function()
      local class_of_students = { students = {} }

      local handle_object_with_list = stream.object(function()
        return {
          class = function()
            local _class = ''
            return function(part, complete)
              _class = _class .. part

              if complete then
                class_of_students.class = _class
              end
            end
          end,
          students = stream.list(function()
            return {
              name = function()
                local _name = ''

                return function(part, is_complete)
                  _name = _name .. part

                  if is_complete then
                    table.insert(class_of_students.students, {
                      name = _name,
                    })
                  end
                end
              end,
            }
          end),
        }
      end)()

      handle_object_with_list('{"class":"math')
      handle_object_with_list('","students":[')
      assert.are.equal('math', class_of_students.class)

      handle_object_with_list('{"name":"jo')
      handle_object_with_list('e"},')
      assert.are.equal(1, #class_of_students.students)
      assert.are.equal('joe', class_of_students.students[1].name)

      handle_object_with_list('{"name":"ja')
      handle_object_with_list('ne"},')
      assert.are.equal(2, #class_of_students.students)
      assert.are.equal('jane', class_of_students.students[2].name)

      handle_object_with_list('{"name":"jac')
      handle_object_with_list('k"}')
      handle_object_with_list(']}', true)
      assert.are.equal(3, #class_of_students.students)
      assert.are.equal('jack', class_of_students.students[3].name)
    end)
  end)
end)
