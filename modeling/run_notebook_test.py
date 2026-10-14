import nbformat
import sys
import matplotlib
matplotlib.use('Agg')

def test_notebook():
    with open('dsp_mathematical_modeling.ipynb', 'r', encoding='utf-8') as f:
        nb = nbformat.read(f, as_version=4)

    env = {}
    code_cell_idx = 0
    for i, cell in enumerate(nb.cells):
        if cell.cell_type == 'code':
            code_cell_idx += 1
            source = cell.source
            try:
                exec(source, env)
                print(f"Cell {code_cell_idx} (raw cell {i+1}) passed OK")
            except Exception as e:
                print(f"Cell {code_cell_idx} (raw cell {i+1}) failed: {e}")
                import traceback
                traceback.print_exc()
                sys.exit(1)

    print("\nALL NOTEBOOK CODE CELLS PASSED PERFECTLY!")

if __name__ == '__main__':
    test_notebook()
